import CryptoKit
import XCTest
import UserNotifications
@testable import OpenCody___An_OpenCode_Client

/// Push protocol (OC-NOTIFY-3) against `opencody-push/SPEC.md`: crypto test vectors (§4.1),
/// pairing string (§3), message → notification (§5, §6.4), dedupe with local alerts, actions (§6.5).
@MainActor
final class PushTests: XCTestCase {

    private let key = Data(0..<32)
    private let nonce = Data([0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab])
    private let deviceId = "AAECAwQFBgcICQoLDA0ODw"
    private let server = UUID()

    private let plaintext1 = #"{"v":1,"type":"permission.asked","server":"homelab","directory":"/srv/app","sessionID":"ses_123","title":"Fix login","text":"bash: rm -rf build","requestID":"per_456","ts":1767225600000}"#
    private let combined1 = "oKGio6SlpqeoqaqrnToKD3/6Lp0WHPe2JUDirhXeNHnhxCsD8iBH9RTOESP+VDSa3VQ2T32mJqBmF+aVJnlkZEC0cwwkPX8x1gmnipaT9h1GioWQhMDTOvyrv8mkZMXtgeOjWJ0QTcWAqH62o6ZfwnfC6rmk+UA5/aiBR0M5D4zyF+9ZV7v8npY3kz6tK5ANvmKtZVF5nP57JvX0pPvfDs+ln/+JhPnXleVETrRHK4SASGw09nkJGF7lgNZFFMiuMlaeDrL/KLur1YU566wy9BNC3pxkeQ=="
    private let plaintext2 = #"{"v":1,"type":"session.finished","server":"Büro 🖥","sessionID":"ses_1","text":"Session finished","ts":0}"#
    private let combined2 = "oKGio6SlpqeoqaqrnToKD3/6Lp0WHPe2JUDirRXfKnn92WwK9WBP9RfOESP+VDSa3VQ2T32mJorKxvGWZ+vZ3sfyNlwyO3gtzR/r+fCev01DwJe/xcDTOvurtM7vMYn3oLLqE4EbHvzY9CTn5+FPiS+M++i84TYtnI0ulko0MWtPbRZkoErwvg=="

    // MARK: - Crypto (§4.1)

    func testSealMatchesSpecVectors() throws {
        let fixed = try AES.GCM.Nonce(data: nonce)
        XCTAssertEqual(try PushCrypto.seal(Data(plaintext1.utf8), key: key, deviceId: deviceId, nonce: fixed), combined1)
        XCTAssertEqual(try PushCrypto.seal(Data(plaintext2.utf8), key: key, deviceId: deviceId, nonce: fixed), combined2)
    }

    func testOpenSpecVectors() throws {
        XCTAssertEqual(String(decoding: try PushCrypto.open(combined1, key: key, deviceId: deviceId), as: UTF8.self), plaintext1)
        XCTAssertEqual(String(decoding: try PushCrypto.open(combined2, key: key, deviceId: deviceId), as: UTF8.self), plaintext2)
    }

    func testOpenRejectsOtherDeviceAndKey() {
        XCTAssertThrowsError(try PushCrypto.open(combined1, key: key, deviceId: "BBECAwQFBgcICQoLDA0ODw"))
        XCTAssertThrowsError(try PushCrypto.open(combined1, key: Data(repeating: 0, count: 32), deviceId: deviceId))
        XCTAssertThrowsError(try PushCrypto.open("not base64", key: key, deviceId: deviceId))
    }

    func testSealUsesFreshNonce() throws {
        let a = try PushCrypto.seal(Data("x".utf8), key: key, deviceId: deviceId)
        let b = try PushCrypto.seal(Data("x".utf8), key: key, deviceId: deviceId)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try PushCrypto.open(a, key: key, deviceId: deviceId), Data("x".utf8))
    }

    func testDecodesSpecExamplePairingString() throws {
        let example = "eyJ2IjoxLCJyZWxheSI6Imh0dHBzOi8vcHVzaC53aWxsc29mdHdhcmVzb2x1dGlvbnMuZGUiLCJkZXZpY2VJZCI6IkFBRUNBd1FGQmdjSUNRb0xEQTBPRHciLCJzZWNyZXQiOiJjMlZqY21WMExXNXZkQzF5WldGc0xXVjRZVzF3YkdVdGIyNXNlUzB4TWpNIiwia2V5IjoiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSJ9"
        let fields = try XCTUnwrap(PairingString.decode(example))
        XCTAssertEqual(fields.relay, "https://push.willsoftwaresolutions.de")
        XCTAssertEqual(fields.deviceId, deviceId)
        XCTAssertEqual(fields.secret, "c2VjcmV0LW5vdC1yZWFsLWV4YW1wbGUtb25seS0xMjM")
        XCTAssertEqual(Base64URL.decode(fields.key), Data(repeating: 0, count: 32))
    }

    func testPairingStringRoundTripsWithoutPadding() throws {
        let string = PairingString.encode(relay: "https://relay.test/", deviceId: deviceId, secret: "s3cr3t", key: key)
        XCTAssertFalse(string.contains("="))
        XCTAssertFalse(string.contains("+") || string.contains("/"))
        let fields = try XCTUnwrap(PairingString.decode(string))
        XCTAssertEqual(fields.relay, "https://relay.test")
        XCTAssertEqual(fields.secret, "s3cr3t")
        XCTAssertEqual(Base64URL.decode(fields.key), key)
    }

    func testPairingStringRejectsWrongVersionAndShortKey() {
        let v2 = Base64URL.encode(Data(#"{"v":2,"relay":"https://r","deviceId":"a","secret":"b","key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"}"#.utf8))
        let short = Base64URL.encode(Data(#"{"v":1,"relay":"https://r","deviceId":"a","secret":"b","key":"AAEC"}"#.utf8))
        XCTAssertNil(PairingString.decode(v2))
        XCTAssertNil(PairingString.decode(short))
        XCTAssertNil(PairingString.decode("%%%"))
    }

    // MARK: - Envelope and message (§2.6, §5)

    func testEnvelopeFromAPNsUserInfo() throws {
        let info: [AnyHashable: Any] = ["aps": ["category": "OC_PERMISSION"], "ocp": ["v": 1, "d": deviceId, "c": combined1]]
        let envelope = try XCTUnwrap(PushEnvelope(userInfo: info))
        XCTAssertEqual(envelope.deviceId, deviceId)
        let message = try envelope.open(key: key)
        XCTAssertEqual(message.type, "permission.asked")
        XCTAssertEqual(message.requestID, "per_456")
        XCTAssertEqual(message.ts, 1_767_225_600_000)
        XCTAssertNil(PushEnvelope(userInfo: ["ocp": ["v": 2, "d": deviceId, "c": combined1]]))
        XCTAssertNil(PushEnvelope(userInfo: ["aps": [:]]))
    }

    func testIgnoresUnknownVersionAndStaleMessages() throws {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let message = try PushMessage.decode(Data(plaintext1.utf8))
        XCTAssertTrue(message.isDeliverable(now: now))
        XCTAssertFalse(message.isDeliverable(now: now.addingTimeInterval(25 * 3600)))
        var future = message
        future.v = 2
        XCTAssertFalse(future.isDeliverable(now: now))
    }

    // MARK: - Presentation (§6.4)

    private func content(_ json: String) throws -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "OpenCode"
        content.body = "OpenCode needs your attention"
        try PushMessage.decode(Data(json.utf8)).apply(to: content, serverID: server)
        return content
    }

    func testPermissionPresentation() throws {
        let content = try content(plaintext1)
        XCTAssertEqual(content.title, "Fix login")
        XCTAssertEqual(content.subtitle, "homelab · app")
        XCTAssertEqual(content.body, "Permission needed: bash: rm -rf build")
        XCTAssertEqual(content.threadIdentifier, "ses_123")
        XCTAssertEqual(content.categoryIdentifier, "OC_PERMISSION")
        XCTAssertEqual(content.userInfo["requestID"] as? String, "per_456")
        XCTAssertEqual(content.userInfo["replySessionID"] as? String, "ses_123")
        XCTAssertEqual(content.userInfo["dedupe"] as? String, "req:per_456")
        XCTAssertNotNil(content.userInfo["opencody"] as? [String: Any])
        XCTAssertEqual(DeepLink(userInfo: content.userInfo), DeepLink(serverID: server, directory: "/srv/app", sessionID: "ses_123"))
    }

    func testFinishedPresentationWithoutTitleOrDirectory() throws {
        let content = try content(plaintext2)
        XCTAssertEqual(content.title, "OpenCode")
        XCTAssertEqual(content.subtitle, "Büro 🖥")
        XCTAssertEqual(content.body, "Session finished")
        XCTAssertEqual(content.categoryIdentifier, "OC_SESSION")
        XCTAssertEqual(content.userInfo["dedupe"] as? String, "ses_1@0")
    }

    func testSubagentRequestOpensRootAndRepliesToChild() throws {
        let content = try content(#"{"v":1,"type":"form.asked","server":"s","directory":"/a/b/","sessionID":"ses_child","rootSessionID":"ses_root","text":"Which DB?","requestID":"frm_1","ts":5}"#)
        XCTAssertEqual(content.body, "Question: Which DB?")
        XCTAssertEqual(content.subtitle, "s · b")
        XCTAssertEqual(content.threadIdentifier, "ses_root")
        XCTAssertEqual(content.categoryIdentifier, "OC_FORM")
        XCTAssertEqual(content.userInfo["sessionID"] as? String, "ses_root")
        XCTAssertEqual(content.userInfo["replySessionID"] as? String, "ses_child")
    }

    func testFailedPresentation() throws {
        let content = try content(#"{"v":1,"type":"session.failed","server":"s","sessionID":"ses_1","text":"Rate limited","ts":7}"#)
        XCTAssertEqual(content.body, "Failed: Rate limited")
        XCTAssertEqual(content.categoryIdentifier, "OC_SESSION")
    }

    // MARK: - Dedupe with local alerts

    func testDedupeKeys() {
        XCTAssertTrue(AlertKey.isDuplicate("req:per_1", "req:per_1"))
        XCTAssertFalse(AlertKey.isDuplicate("req:per_1", "req:per_2"))
        // Local runs use the session's idle time, push the event time; both mark the end of the run.
        XCTAssertTrue(AlertKey.isDuplicate("ses_1@1000", "ses_1@3500"))
        XCTAssertFalse(AlertKey.isDuplicate("ses_1@1000", "ses_1@60000"))
        XCTAssertFalse(AlertKey.isDuplicate("ses_1@1000", "ses_2@1000"))
        XCTAssertFalse(AlertKey.isDuplicate("req:ses_1@1000", "ses_1@1000"))
    }

    func testLocalAlertsUseSharedCategoriesAndKeys() {
        let raw = SessionAlert.from(v2Event: "permission.asked", data: ["id": "per_1", "sessionID": "ses_child", "action": "bash"])!
        let state = V2SessionState(json: ["id": "ses_child", "parentID": "ses_root"])!
        let alert = raw.resolved(with: state)!
        let request = NotificationContent.requests(for: [alert], server: server)[0]
        XCTAssertEqual(request.identifier, "req:per_1")
        XCTAssertEqual(request.content.categoryIdentifier, "OC_PERMISSION")
        XCTAssertEqual(request.content.userInfo["dedupe"] as? String, "req:per_1")
        XCTAssertEqual(request.content.userInfo["sessionID"] as? String, "ses_root")
        XCTAssertEqual(request.content.userInfo["replySessionID"] as? String, "ses_child")
        XCTAssertEqual(request.content.userInfo["requestID"] as? String, "per_1")
    }

    func testFreshAlertsSkipDelivered() {
        let alerts = [
            SessionAlert(kind: .finished, sessionID: "ses_1", key: "ses_1@1000"),
            SessionAlert(kind: .permission, sessionID: "ses_2", requestID: "per_9", key: "req:per_9"),
        ]
        XCTAssertEqual(AlertKey.fresh(alerts, delivered: ["ses_1@1200"]).map(\.key), ["req:per_9"])
    }

    // MARK: - Actions (§6.5)

    func testPermissionActionsMapToReply() throws {
        let info: [AnyHashable: Any] = ["serverID": server.uuidString, "sessionID": "ses_root", "replySessionID": "ses_child", "requestID": "per_1"]
        let reply = try XCTUnwrap(PermissionAction.reply(action: "PERMISSION_ALWAYS", userInfo: info))
        XCTAssertEqual(reply.serverID, server)
        XCTAssertEqual(reply.path, "/api/session/ses_child/permission/per_1/reply")
        XCTAssertEqual(reply.decision, "always")
        XCTAssertEqual(PermissionAction.reply(action: "PERMISSION_ONCE", userInfo: info)?.decision, "once")
        XCTAssertEqual(PermissionAction.reply(action: "PERMISSION_REJECT", userInfo: info)?.decision, "reject")
        XCTAssertNil(PermissionAction.reply(action: UNNotificationDefaultActionIdentifier, userInfo: info))
        XCTAssertNil(PermissionAction.reply(action: "PERMISSION_ONCE", userInfo: ["serverID": server.uuidString]))
    }

    func testPermissionCategoryHasAuthenticatedActions() {
        let categories = NotificationCategories.all
        XCTAssertEqual(Set(categories.map(\.identifier)), ["OC_SESSION", "OC_PERMISSION", "OC_FORM"])
        let permission = categories.first { $0.identifier == "OC_PERMISSION" }!
        XCTAssertEqual(permission.actions.map(\.identifier), ["PERMISSION_ONCE", "PERMISSION_ALWAYS", "PERMISSION_REJECT"])
        XCTAssertTrue(permission.actions.allSatisfy { $0.options.contains(.authenticationRequired) })
        XCTAssertTrue(permission.actions.last!.options.contains(.destructive))
    }

    // MARK: - Setup guide

    func testAgentPromptCarriesPairingAndRules() {
        let prompt = PushSetupGuide.agentPrompt(pairing: "PAIRING123", serverName: "homelab")
        XCTAssertTrue(prompt.contains("PAIRING123"))
        XCTAssertTrue(prompt.contains("opencode plugin add opencody-notify"))
        XCTAssertTrue(prompt.contains("OPENCODY_PAIRING"))
        XCTAssertTrue(prompt.contains("opencode.jsonc"))
    }
}
