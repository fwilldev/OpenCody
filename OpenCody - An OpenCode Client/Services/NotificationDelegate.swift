import Foundation
import UserNotifications

/// Shows notifications while the app is open, opens their session when tapped and
/// answers permissions from the notification's buttons.
/// Installed at launch, so the tap that launched the app is not lost.
@Observable
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// The tapped notification's session, until `RootView` opens it.
    var pendingLink: DeepLink?

    /// The session on screen; its own notifications stay quiet.
    @ObservationIgnored var viewingSessionID: () -> String? = { nil }

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(NotificationCategories.all)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let sessionID = info["sessionID"] as? String
        let viewing = await MainActor.run { viewingSessionID() }
        if sessionID != nil && sessionID == viewing { return [] }
        // A push the live connection already announced.
        if info["opencody"] != nil, let key = info["dedupe"] as? String {
            let shown = await center.deliveredNotifications().filter { $0.request.identifier != notification.request.identifier }
            if shown.contains(where: { ($0.request.content.userInfo["dedupe"] as? String).map { AlertKey.isDuplicate($0, key) } ?? false }) {
                return []
            }
        }
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let reply = PermissionAction.reply(action: response.actionIdentifier, userInfo: info) {
            await answer(reply, info: info)
            return
        }
        guard let link = DeepLink(userInfo: info) else { return }
        await MainActor.run { pendingLink = link }
    }

    /// Replies straight to the OpenCode server, never via the relay. 404 means it was already answered.
    private func answer(_ reply: PermissionAction.Reply, info: [AnyHashable: Any]) async {
        guard let server = ServerStore.shared.load().first(where: { $0.id == reply.serverID }) else { return }
        do {
            try await server.makeAPIClient().requestVoid(.v2(reply.path, method: .POST, json: ["decision": reply.decision]))
        } catch OpenCodeError.notFound {
        } catch {
            let content = UNMutableNotificationContent()
            content.title = "Couldn't send your answer"
            content.body = "\(server.name) didn't respond. Open the session to answer there."
            content.sound = .default
            content.userInfo = info
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "reply-failed-\(UUID().uuidString)", content: content, trigger: nil)
            )
        }
    }
}

/// Buttons on permission notifications (SPEC §6.5), local and push alike.
nonisolated enum PermissionAction: String, CaseIterable {
    case once = "PERMISSION_ONCE"
    case always = "PERMISSION_ALWAYS"
    case reject = "PERMISSION_REJECT"

    struct Reply: Equatable {
        let serverID: UUID
        let path: String
        let decision: String
    }

    var title: String {
        switch self {
        case .once: "Allow once"
        case .always: "Always allow"
        case .reject: "Deny"
        }
    }

    var decision: PermissionReplyDecision {
        switch self {
        case .once: .once
        case .always: .always
        case .reject: .reject
        }
    }

    static func reply(action: String, userInfo: [AnyHashable: Any]) -> Reply? {
        guard let action = PermissionAction(rawValue: action),
              let server = (userInfo["serverID"] as? String).flatMap(UUID.init(uuidString:)),
              let requestID = userInfo["requestID"] as? String,
              let session = userInfo["replySessionID"] as? String ?? userInfo["sessionID"] as? String
        else { return nil }
        return Reply(serverID: server, path: "/api/session/\(session)/permission/\(requestID)/reply",
                     decision: action.decision.rawValue)
    }
}

enum NotificationCategories {
    static var all: Set<UNNotificationCategory> {
        // The phone must be unlocked to approve anything.
        let actions = PermissionAction.allCases.map { action in
            UNNotificationAction(identifier: action.rawValue, title: action.title,
                                 options: action == .reject ? [.authenticationRequired, .destructive] : [.authenticationRequired])
        }
        return [
            UNNotificationCategory(identifier: NotificationCategory.permission, actions: actions, intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.form, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.session, actions: [], intentIdentifiers: []),
        ]
    }
}
