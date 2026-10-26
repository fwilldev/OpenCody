import XCTest
import UserNotifications
@testable import OpenCody___An_OpenCode_Client

/// Notifications for OpenCode 2.x servers (OC-NOTIFY-1): event mapping, dedupe and catch-up.
///
/// Fixtures follow `packages/schema/src/session-event.ts`, `permission.ts`, `form.ts` and
/// `session.ts` of OpenCode 2.x.
@MainActor
final class SessionAlertTests: XCTestCase {

    private typealias JSON = [String: Any]
    private var defaults: UserDefaults!
    private let server = UUID()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SessionAlertTests")
        defaults.removePersistentDomain(forName: "SessionAlertTests")
    }

    private func session(
        _ id: String, parent: String? = nil, outcome: String? = "succeeded",
        idle: Double? = 2000, viewed: Double? = nil, title: String = "Fix login"
    ) -> JSON {
        var time: JSON = ["created": 1000, "updated": 2000]
        if let idle { time["idle"] = idle }
        if let viewed { time["viewed"] = viewed }
        var raw: JSON = ["id": id, "title": title, "time": time, "location": ["directory": "/srv/repo"]]
        if let parent { raw["parentID"] = parent }
        if let outcome { raw["outcome"] = outcome }
        return raw
    }

    private func states(_ raws: [JSON]) -> [V2SessionState] { raws.compactMap(V2SessionState.init(json:)) }

    private let permission: JSON = [
        "id": "per_1", "sessionID": "ses_1", "action": "bash", "resources": ["npm test"],
    ]
    private let form: JSON = [
        "id": "frm_1", "sessionID": "ses_1", "title": "Questions",
        "metadata": ["kind": "question"],
        "fields": [["key": "q0", "type": "string", "title": "Which database?"]],
    ]

    // MARK: - Event mapping

    func testSucceededIsFinished() {
        let alert = SessionAlert.from(v2Event: "session.execution.succeeded", data: ["sessionID": "ses_1"])
        XCTAssertEqual(alert, SessionAlert(kind: .finished, sessionID: "ses_1"))
    }

    func testFailedCarriesErrorText() {
        let alert = SessionAlert.from(
            v2Event: "session.execution.failed",
            data: ["sessionID": "ses_1", "error": ["type": "provider", "message": "Rate limited"]]
        )
        XCTAssertEqual(alert?.kind, .failed)
        XCTAssertEqual(alert?.detail, "Rate limited")
    }

    func testUserAndSupersededInterruptsAreSilent() {
        for reason in ["user", "superseded", "shutdown"] {
            XCTAssertNil(SessionAlert.from(
                v2Event: "session.execution.interrupted", data: ["sessionID": "ses_1", "reason": reason]
            ), reason)
        }
    }

    func testInactivityInterruptIsAFailure() {
        let alert = SessionAlert.from(
            v2Event: "session.execution.interrupted", data: ["sessionID": "ses_1", "reason": "inactivity"]
        )
        XCTAssertEqual(alert?.kind, .failed)
    }

    func testPermissionShowsToolNotRequestID() {
        let alert = SessionAlert.from(v2Event: "permission.asked", data: permission)
        XCTAssertEqual(alert?.kind, .permission)
        XCTAssertEqual(alert?.requestID, "per_1")
        XCTAssertEqual(alert?.detail, "bash: npm test")
        var titled = permission
        titled["metadata"] = ["title": "Run tests"]
        XCTAssertEqual(SessionAlert.from(v2Event: "permission.asked", data: titled)?.detail, "Run tests")
    }

    func testFormShowsQuestionTitle() {
        let alert = SessionAlert.from(v2Event: "form.created", data: ["form": form])
        XCTAssertEqual(alert?.kind, .form)
        XCTAssertEqual(alert?.requestID, "frm_1")
        XCTAssertEqual(alert?.detail, "Which database?")
    }

    func testGlobalFormsAndOtherEventsAreIgnored() {
        var global = form
        global["sessionID"] = "global"
        XCTAssertNil(SessionAlert.from(v2Event: "form.created", data: ["form": global]))
        XCTAssertNil(SessionAlert.from(v2Event: "session.execution.started", data: ["sessionID": "ses_1"]))
    }

    func testCategoriesAreStable() {
        XCTAssertEqual(SessionAlert.Kind.allCases.map(\.rawValue),
                       ["session.finished", "session.failed", "permission.asked", "form.asked"])
    }

    func testTranslatorEmitsAlertsForEveryFolder() async throws {
        let client = APIClient(baseURL: "http://127.0.0.1:9", username: "", password: "", apiVersion: .v2)
        let raw = #"{"id":"evt_1","type":"permission.asked","location":{"directory":"/other"},"data":{"id":"per_1","sessionID":"ses_1","action":"edit","resources":["a.txt"]}}"#
        let output = await V2EventTranslator(client: client).translate(raw)
        let wrapped = try XCTUnwrap(output.last)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(wrapped.utf8)) as? JSON)
        XCTAssertNil(object["directory"], "the directory filter must not drop alerts")
        let payload = try XCTUnwrap(object["payload"] as? JSON)
        let data = try JSONSerialization.data(withJSONObject: payload)
        let event = try SSEEvent.parse(eventName: try XCTUnwrap(payload["type"] as? String),
                                       data: String(decoding: data, as: UTF8.self))
        guard case .sessionAlert(let alert) = event else { return XCTFail("Expected alert, got \(event)") }
        XCTAssertEqual(alert.requestID, "per_1")
        XCTAssertEqual(alert.detail, "edit: a.txt")
    }

    // MARK: - Resolving against the session

    func testSubagentRunsAreNotNotified() throws {
        let child = try XCTUnwrap(V2SessionState(json: session("ses_2", parent: "ses_1")))
        XCTAssertNil(SessionAlert(kind: .finished, sessionID: "ses_2").resolved(with: child))
    }

    func testSubagentRequestsOpenTheRootSession() throws {
        let child = try XCTUnwrap(V2SessionState(json: session("ses_2", parent: "ses_1")))
        let alert = SessionAlert(kind: .permission, sessionID: "ses_2", requestID: "per_1").resolved(with: child)
        XCTAssertEqual(alert?.sessionID, "ses_1")
        XCTAssertEqual(alert?.key, "req:per_1")
    }

    func testRunKeyIsSessionAndIdleTime() throws {
        let root = try XCTUnwrap(V2SessionState(json: session("ses_1")))
        let alert = SessionAlert(kind: .finished, sessionID: "ses_1").resolved(with: root)
        XCTAssertEqual(alert?.key, "ses_1@2000")
        XCTAssertEqual(alert?.sessionTitle, "Fix login")
        XCTAssertEqual(alert?.directory, "/srv/repo")
    }

    // MARK: - Ledger

    func testLedgerRemembersAcrossInstances() {
        XCTAssertTrue(NotificationLedger(defaults: defaults).insert("ses_1@2000"))
        XCTAssertFalse(NotificationLedger(defaults: defaults).insert("ses_1@2000"))
        XCTAssertTrue(NotificationLedger(defaults: defaults).insert("ses_1@3000"))
    }

    func testLedgerIsBounded() {
        let ledger = NotificationLedger(defaults: defaults, capacity: 3)
        for key in ["a", "b", "c", "d"] { ledger.insert(key) }
        XCTAssertTrue(ledger.insert("a"))
        XCTAssertFalse(ledger.insert("d"))
    }

    func testLedgerMovesIntoTheAppGroupOnce() throws {
        let legacy = try XCTUnwrap(UserDefaults(suiteName: "SessionAlertTests.legacy"))
        legacy.removePersistentDomain(forName: "SessionAlertTests.legacy")
        legacy.set(["ses_1@2000"], forKey: "notification.ledger")
        legacy.set([server.uuidString], forKey: "notification.ledger.baselines")
        NotificationLedger(defaults: defaults).insert("req:per_1")

        NotificationLedger.migrate(from: legacy, to: defaults)
        let ledger = NotificationLedger(defaults: defaults)
        XCTAssertFalse(ledger.insert("ses_1@2000"))
        XCTAssertFalse(ledger.insert("req:per_1"))
        XCTAssertFalse(ledger.markBaseline(server))
        XCTAssertNil(legacy.array(forKey: "notification.ledger"))

        legacy.set(["ses_9@1"], forKey: "notification.ledger")
        NotificationLedger.migrate(from: legacy, to: defaults)
        XCTAssertTrue(ledger.insert("ses_9@1"), "migrates only once")
    }

    // MARK: - Catch-up

    private func plan(_ sessions: [JSON], permissions: [JSON] = [], forms: [JSON] = [], viewing: String? = nil) -> [SessionAlert] {
        NotificationCatchUp.plan(
            server: server, sessions: states(sessions), permissions: permissions, forms: forms,
            viewing: viewing, ledger: NotificationLedger(defaults: defaults)
        )
    }

    func testFirstCatchUpOnlyRecordsHistory() {
        XCTAssertEqual(plan([session("ses_1")]), [])
        XCTAssertEqual(plan([session("ses_1")]), [])
        XCTAssertEqual(plan([session("ses_1"), session("ses_2", idle: 5000)]).map(\.sessionID), ["ses_2"])
    }

    func testCatchUpNotifiesUnreadOutcomesOnce() {
        _ = plan([])
        let sessions = [
            session("ses_1"),
            session("ses_2", outcome: "failed"),
            session("ses_3", viewed: 2000),
            session("ses_4", outcome: "interrupted"),
            session("ses_5", outcome: nil, idle: nil),
            session("ses_6", parent: "ses_1"),
        ]
        let alerts = plan(sessions)
        XCTAssertEqual(alerts.map(\.sessionID), ["ses_1", "ses_2"])
        XCTAssertEqual(alerts.map(\.kind), [.finished, .failed])
        XCTAssertEqual(plan(sessions), [])
    }

    func testCatchUpWithoutSeenBusyStillNotifiesNewRun() {
        _ = plan([session("ses_1", idle: 2000, viewed: 2000)])
        XCTAssertEqual(plan([session("ses_1", idle: 9000, viewed: 2000)]).map(\.key), ["ses_1@9000"])
    }

    func testCatchUpSkipsTheOpenSession() {
        _ = plan([])
        XCTAssertEqual(plan([session("ses_1")], viewing: "ses_1"), [])
        XCTAssertEqual(plan([session("ses_1")]), [], "the open session counts as seen")
    }

    func testCatchUpIncludesOpenRequests() {
        _ = plan([])
        let alerts = plan([session("ses_1", outcome: nil, idle: nil)], permissions: [permission], forms: [form])
        XCTAssertEqual(alerts.map(\.kind), [.permission, .form])
        XCTAssertEqual(alerts.map(\.sessionTitle), ["Fix login", "Fix login"])
        XCTAssertEqual(plan([], permissions: [permission], forms: [form]), [])
    }

    func testLiveAlertSuppressesCatchUp() throws {
        _ = plan([])
        let ledger = NotificationLedger(defaults: defaults)
        let state = try XCTUnwrap(V2SessionState(json: session("ses_1")))
        let live = try XCTUnwrap(SessionAlert(kind: .finished, sessionID: "ses_1").resolved(with: state))
        XCTAssertTrue(ledger.insert(live.key))
        XCTAssertEqual(plan([session("ses_1")]), [])
    }

    func testDeliveredPushSuppressesCatchUp() {
        _ = plan([])
        // What the Notification Service Extension records, even if the user swipes the push away.
        NotificationLedger(defaults: defaults).insert("ses_1@2000")
        NotificationLedger(defaults: defaults).insert("~ses_2@2400")
        XCTAssertEqual(plan([session("ses_1"), session("ses_2"), session("ses_3")]).map(\.sessionID), ["ses_3"])
    }

    // MARK: - Content

    func testRequestsCarryDeepLink() throws {
        let alert = SessionAlert(kind: .failed, sessionID: "ses_1", detail: "Rate limited",
                                 sessionTitle: "Fix login", directory: "/srv/repo", key: "ses_1@2000")
        let requests = NotificationContent.requests(for: [alert], server: server)
        let content = try XCTUnwrap(requests.first?.content)
        XCTAssertEqual(requests.first?.identifier, AlertKey.identifier("ses_1@2000"))
        XCTAssertEqual(content.categoryIdentifier, "OC_SESSION")
        XCTAssertEqual(content.body, "Fix login: Rate limited")
        XCTAssertEqual(DeepLink(userInfo: content.userInfo),
                       DeepLink(serverID: server, directory: "/srv/repo", sessionID: "ses_1"))
    }

    func testMoreThanThreeAlertsBecomeOneSummary() {
        let alerts = (1...4).map { SessionAlert(kind: .finished, sessionID: "ses_\($0)", key: "ses_\($0)@1") }
        XCTAssertEqual(NotificationContent.requests(for: Array(alerts.prefix(3)), server: server).count, 3)
        let summary = NotificationContent.requests(for: alerts, server: server)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.first?.content.body, "4 sessions need your attention.")
    }
}
