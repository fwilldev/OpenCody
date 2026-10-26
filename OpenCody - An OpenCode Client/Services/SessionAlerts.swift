import Foundation
import UserNotifications

/// Something on an OpenCode 2.x server the user should hear about. 1.x servers get none.
nonisolated struct SessionAlert: Codable, Equatable, Sendable {
    /// Raw values match the push message `type`.
    enum Kind: String, Codable, CaseIterable, Sendable {
        case finished = "session.finished"
        case failed = "session.failed"
        case permission = "permission.asked"
        case form = "form.asked"

        var category: String { NotificationCategory.forType(rawValue) }
    }

    var kind: Kind
    var sessionID: String
    /// Permission or form ID, for requests.
    var requestID: String?
    /// The session a request belongs to, which is where it is answered (may be a subagent).
    var replySessionID: String?
    /// Error text, or the tool or question a request is about.
    var detail: String?
    var sessionTitle: String?
    var directory: String?
    /// Dedupe key: session and idle time for runs, request ID for requests.
    var key: String = ""

    typealias JSON = [String: Any]

    /// Maps one `/api/event` event; `nil` for events that don't notify.
    static func from(v2Event type: String, data: JSON) -> SessionAlert? {
        let sessionID = data["sessionID"] as? String ?? ""
        let alert: SessionAlert
        switch type {
        case "session.execution.succeeded":
            alert = SessionAlert(kind: .finished, sessionID: sessionID)
        case "session.execution.failed":
            alert = SessionAlert(kind: .failed, sessionID: sessionID, detail: (data["error"] as? JSON)?["message"] as? String)
        // `user` and `superseded` are the user's own doing, `shutdown` resumes later.
        case "session.execution.interrupted" where data["reason"] as? String == "inactivity":
            alert = SessionAlert(kind: .failed, sessionID: sessionID, detail: "Stopped after no activity.")
        case "permission.asked":
            alert = SessionAlert(kind: .permission, sessionID: sessionID, requestID: data["id"] as? String,
                                 replySessionID: sessionID, detail: permissionTitle(data))
        case "form.created":
            guard let form = data["form"] as? JSON else { return nil }
            let field = (form["fields"] as? [JSON])?.first
            alert = SessionAlert(kind: .form, sessionID: form["sessionID"] as? String ?? "",
                                 requestID: form["id"] as? String, replySessionID: form["sessionID"] as? String,
                                 detail: field?["title"] as? String ?? form["title"] as? String)
        default:
            return nil
        }
        // MCP elicitations use the `global` owner, which is no session to open.
        guard !alert.sessionID.isEmpty, alert.sessionID != "global" else { return nil }
        return alert
    }

    private static func permissionTitle(_ data: JSON) -> String? {
        if let title = (data["metadata"] as? JSON)?["title"] as? String, !title.isEmpty { return title }
        guard let action = data["action"] as? String else { return nil }
        guard let resource = (data["resources"] as? [String])?.first(where: { !$0.isEmpty }) else { return action }
        return "\(action): \(resource)"
    }

    /// Fills in the session and dedupe key. Subagent runs return `nil`; subagent
    /// requests point at the parent, where the user answers them.
    func resolved(with session: V2SessionState) -> SessionAlert? {
        var alert = self
        alert.sessionTitle = session.title
        alert.directory = session.directory
        switch kind {
        case .finished, .failed:
            guard session.parentID == nil, let key = session.idleKey else { return nil }
            alert.key = key
        case .permission, .form:
            alert.sessionID = session.parentID ?? session.id
            alert.key = "req:\(requestID ?? "")"
        }
        return alert
    }
}

/// The parts of a 2.x `Session.Info` that decide whether it is unread.
nonisolated struct V2SessionState: Equatable, Sendable {
    let id: String
    let parentID: String?
    let title: String?
    let directory: String?
    let outcome: String?
    let idle: Double?
    let viewed: Double?

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        let time = json["time"] as? [String: Any]
        self.id = id
        parentID = json["parentID"] as? String
        title = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        directory = (json["location"] as? [String: Any])?["directory"] as? String
        outcome = json["outcome"] as? String
        idle = time?["idle"] as? Double
        viewed = time?["viewed"] as? Double
    }

    /// Same rule as the OpenCode app: the last run ended after anyone last viewed it.
    var isUnread: Bool {
        guard let idle else { return false }
        return viewed.map { idle > $0 } ?? true
    }

    var idleKey: String? { idle.map { "\(id)@\(Int64($0))" } }
}

/// Rebuilds missed alerts from server state, since `/api/event` has no replay.
enum NotificationCatchUp {
    typealias JSON = [String: Any]

    /// Alerts to post now, recorded in `ledger`. A server's first catch-up only records,
    /// so updating the app doesn't replay its whole history. The open session counts as seen.
    static func plan(
        server: UUID,
        sessions: [V2SessionState],
        permissions: [JSON],
        forms: [JSON],
        viewing: String?,
        ledger: NotificationLedger
    ) -> [SessionAlert] {
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let runs: [SessionAlert] = sessions.filter(\.isUnread).compactMap { session in
            let kind: SessionAlert.Kind? = switch session.outcome {
            case "succeeded": .finished
            case "failed": .failed
            default: nil
            }
            return kind.flatMap { SessionAlert(kind: $0, sessionID: session.id).resolved(with: session) }
        }
        let requests = permissions.compactMap { SessionAlert.from(v2Event: "permission.asked", data: $0) }
            + forms.compactMap { SessionAlert.from(v2Event: "form.created", data: ["form": $0]) }
        let resolvedRequests: [SessionAlert] = requests.compactMap { request in
            if let session = byID[request.sessionID] { return request.resolved(with: session) }
            var alert = request
            alert.key = "req:\(request.requestID ?? "")"
            return alert
        }

        let firstRun = ledger.markBaseline(server)
        return (runs + resolvedRequests).filter { alert in
            ledger.insert(alert.key) && !firstRun && alert.sessionID != viewing
        }
    }

    /// Reads one 2.x server's state and plans its alerts.
    static func fetch(client: APIClient, server: UUID, viewing: String?, ledger: NotificationLedger) async throws -> [SessionAlert] {
        let list = try await client.v2Data(.get("/api/session", queryItems: [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "order", value: "desc"),
        ])) as? [JSON] ?? []
        let sessions = list.compactMap(V2SessionState.init(json:))

        // Requests are listed per location; pending ones sit in recently used folders.
        // ponytail: only the 8 most recent folders, list `/api/location` if requests go missing.
        var directories: [String] = []
        for directory in sessions.compactMap(\.directory) where !directories.contains(directory) {
            directories.append(directory)
            if directories.count == 8 { break }
        }
        var permissions: [JSON] = []
        var forms: [JSON] = []
        for directory in directories {
            let location = APIEndpoint.v2Location(directory)
            permissions += (try? await client.v2Data(.get("/api/permission/request", queryItems: location))) as? [JSON] ?? []
            forms += (try? await client.v2Data(.get("/api/form", queryItems: location))) as? [JSON] ?? []
        }

        return plan(server: server, sessions: sessions, permissions: permissions, forms: forms,
                    viewing: viewing, ledger: ledger)
    }
}

/// Where tapping a notification leads; carried in its `userInfo`.
nonisolated struct DeepLink: Equatable, Sendable {
    let serverID: UUID
    let directory: String?
    let sessionID: String

    init(serverID: UUID, directory: String?, sessionID: String) {
        self.serverID = serverID
        self.directory = directory
        self.sessionID = sessionID
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let server = (userInfo["serverID"] as? String).flatMap(UUID.init(uuidString:)),
              let sessionID = userInfo["sessionID"] as? String
        else { return nil }
        self.init(serverID: server, directory: userInfo["directory"] as? String, sessionID: sessionID)
    }
}

enum NotificationContent {
    /// One request per alert, or a single summary for more than three.
    static func requests(for alerts: [SessionAlert], server: UUID) -> [UNNotificationRequest] {
        guard alerts.count <= 3 else {
            let content = UNMutableNotificationContent()
            content.title = "OpenCody"
            content.body = "\(alerts.count) sessions need your attention."
            content.sound = .default
            content.userInfo = ["serverID": server.uuidString]
            return [UNNotificationRequest(identifier: "summary-\(UUID().uuidString)", content: content, trigger: nil)]
        }
        return alerts.map { alert in
            UNNotificationRequest(identifier: AlertKey.identifier(alert.key), content: content(for: alert, server: server), trigger: nil)
        }
    }

    private static func content(for alert: SessionAlert, server: UUID) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let title = alert.sessionTitle
        switch alert.kind {
        case .finished:
            content.title = "Session finished"
            content.body = title ?? "A session finished."
        case .failed:
            content.title = "Session failed"
            content.body = [title, alert.detail].compactMap { $0 }.joined(separator: ": ")
            if content.body.isEmpty { content.body = "A session failed." }
        case .permission:
            content.title = "Permission needed"
            content.subtitle = title ?? ""
            content.body = alert.detail ?? "A tool is waiting for your approval."
        case .form:
            content.title = "Question from the agent"
            content.subtitle = title ?? ""
            content.body = alert.detail ?? "The agent needs your input."
        }
        content.sound = .default
        content.categoryIdentifier = alert.kind.category
        content.threadIdentifier = alert.sessionID
        // Same keys as decrypted pushes (`PushMessage.apply`).
        var info: [String: Any] = ["serverID": server.uuidString, "sessionID": alert.sessionID, "dedupe": alert.key]
        info["directory"] = alert.directory
        info["requestID"] = alert.requestID
        info["replySessionID"] = alert.replySessionID
        content.userInfo = info
        return content
    }
}

extension AlertKey {
    /// Alerts not already on screen, e.g. as a push that arrived first.
    static func fresh(_ alerts: [SessionAlert], delivered: [String]) -> [SessionAlert] {
        alerts.filter { alert in !delivered.contains { isDuplicate($0, alert.key) } }
    }
}
