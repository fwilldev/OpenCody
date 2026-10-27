import CryptoKit
import XCTest
import UserNotifications
@testable import OpenCody___An_OpenCode_Client

/// Push protocol (OC-NOTIFY-3) against `opencody-push/SPEC.md`: crypto test vectors (§4.1),
/// pairing string (§3), message → notification (§5, §6.4), dedupe, device token, actions (§6.5).
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
        XCTAssertEqual(content.userInfo["dedupe"] as? String, "~ses_1@0", "payloads without key match by time window")
    }

    func testPushKeyIsUsedExactly() throws {
        let json = #"{"v":1,"type":"session.finished","server":"s","sessionID":"ses_1","text":"Session finished","key":"ses_1@1767225600123","ts":1767225600000}"#
        XCTAssertEqual(try content(json).userInfo["dedupe"] as? String, "ses_1@1767225600123")
        let permission = #"{"v":1,"type":"permission.asked","server":"s","sessionID":"ses_1","text":"t","requestID":"per_1","key":"req:per_1","ts":1}"#
        XCTAssertEqual(try content(permission).userInfo["dedupe"] as? String, "req:per_1")
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

    // MARK: - Dedupe

    func testDedupeKeys() {
        XCTAssertTrue(AlertKey.isDuplicate("req:per_1", "req:per_1"))
        XCTAssertFalse(AlertKey.isDuplicate("req:per_1", "req:per_2"))
        // Exact keys from the plugin: a second run moments later is a new alert.
        XCTAssertFalse(AlertKey.isDuplicate("ses_1@1000", "ses_1@3500"))
        // Old payloads carry only the event time, which is close to the session's idle time.
        XCTAssertTrue(AlertKey.isDuplicate("~ses_1@1000", "ses_1@3500"))
        XCTAssertTrue(AlertKey.isDuplicate("ses_1@3500", "~ses_1@1000"))
        XCTAssertFalse(AlertKey.isDuplicate("~ses_1@1000", "ses_1@60000"))
        XCTAssertFalse(AlertKey.isDuplicate("~ses_1@1000", "ses_2@1000"))
        XCTAssertFalse(AlertKey.isDuplicate("req:ses_1@1000", "~ses_1@1000"))
    }

    // MARK: - Settings

    func testPushStatusPerServer() {
        let pairing = PushPairing(serverID: server, relay: "r", deviceId: "d", secret: "s", key: Data(), token: "t", env: "production")
        var broken = pairing
        broken.broken = true
        XCTAssertEqual(PushStatus(apiVersion: .v1, pairing: pairing), .unsupported)
        XCTAssertEqual(PushStatus(apiVersion: .v2, pairing: nil), .off)
        XCTAssertEqual(PushStatus(apiVersion: .v2, pairing: pairing), .paired)
        XCTAssertEqual(PushStatus(apiVersion: .v2, pairing: broken), .broken)
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

    /// The app pairs itself, so the agent only installs and verifies the plugin.
    func testAgentPromptInstallsPluginWithoutPairing() {
        let prompt = PushSetupGuide.agentPrompt(serverName: "homelab")
        XCTAssertTrue(prompt.contains("\"homelab\""))
        XCTAssertTrue(prompt.contains("opencode plugin add opencody-notify"))
        XCTAssertTrue(prompt.contains("~/.config/opencode/opencode.jsonc"))
        XCTAssertTrue(prompt.contains("GET /api/plugin"))
        XCTAssertTrue(prompt.contains("0.4.0"))
        XCTAssertFalse(prompt.contains("OPENCODY_PAIRING"))
    }

    func testHumanStepsInstallRestartTurnOnTest() {
        let steps = PushSetupGuide.humanSteps
        XCTAssertEqual(steps.count, 4)
        XCTAssertTrue(steps[0].contains("opencode plugin add opencody-notify") && steps[0].contains("globally"))
        XCTAssertTrue(steps[1].contains("Restart OpenCode once"))
        XCTAssertTrue(steps[2].contains("Turn on push"))
        XCTAssertTrue(steps[3].contains("Send Test Notification"))
        XCTAssertFalse(steps.joined().contains("OPENCODY_PAIRING"))
    }

    func testSetupCopySaysDeviceNotIPhone() {
        let texts = PushSetupGuide.humanSteps + [PushSetupGuide.agentPrompt(serverName: "s")]
            + [PluginReply.notPaired, .relayFailed(0), .relayFailed(410), .pluginOutdated, .pluginMissing, .sent(server: "lab")].map(\.message)
            + [PushRelay.Failure.unauthorized.errorDescription ?? ""]
        for text in texts { XCTAssertFalse(text.localizedCaseInsensitiveContains("iphone"), text) }
    }

    // MARK: - Server test (plugin RPC, SPEC §6.1 step 7)

    func testServerTestSuccess() {
        XCTAssertEqual(PluginReply(success: Data(#"{"output":{"server":"homelab"}}"#.utf8)), .sent(server: "homelab"))
        XCTAssertTrue(PluginReply.sent(server: "homelab").message.contains("“homelab”"))
        // A 2.x server without the RPC route answers unknown paths with its web app.
        XCTAssertEqual(PluginReply(success: Data("<!doctype html>".utf8)), .serverTooOld)
    }

    func testServerTestRpcErrors() {
        let error = { (json: String) in PluginReply(rpcError: Data(json.utf8)) }
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"not_paired","message":"no pairing","data":{"pairings":1}}"#), .notPaired)
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"relay_failed","message":"relay answered 410","data":{"status":410}}"#), .relayFailed(410))
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"relay_failed","message":"x","data":{"status":0}}"#), .relayFailed(0))
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"rpc.unavailable","message":"RPC is unavailable: opencody-notify"}"#), .pluginMissing)
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"rpc.invalid_input","message":"Missing key"}"#), .failed("Missing key"))
        XCTAssertTrue(PluginReply.relayFailed(0).message.contains(PushService.relayURL))
    }

    /// After `rpc.unavailable`, the plugin list tells plugin 0.2.0 from a missing plugin.
    func testServerTestPluginListFallback() {
        let list = { (entries: String) in PluginReply(plugins: Data(#"{"location":{},"data":[{"id":"opencode.agent","source":{"type":"builtin"},"features":{"server":true},"state":{"status":"active"}}\#(entries)]}"#.utf8)) }
        XCTAssertEqual(list(""), .pluginMissing)
        XCTAssertEqual(list(#",{"id":"opencody-notify","source":{"type":"package","target":"opencody-notify","version":"0.2.0"},"features":{"server":true},"state":{"status":"active"}}"#), .pluginOutdated)
        XCTAssertEqual(list(#",{"id":"opencody-notify","source":{"type":"local","path":"/opt/p"},"features":{"server":true},"state":{"status":"failed","error":"boom"}}"#), .pluginFailed("boom"))
        XCTAssertTrue(PluginReply.pluginOutdated.message.contains("0.4.0"))
    }

    // MARK: - Auto-pair (plugin RPC pair/unpair, SPEC §6.1 step 6, §6.3)

    func testPairReplies() {
        XCTAssertEqual(PluginReply(success: Data(#"{"output":{"server":"homelab","pairings":2}}"#.utf8)), .sent(server: "homelab"))
        let error = { (json: String) in PluginReply(rpcError: Data(json.utf8)) }
        // Plugin 0.3.0 has the RPC but no `pair`; the plugin list then says "outdated".
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"rpc.method_not_found","message":"Unknown RPC method: opencody-notify.pair"}"#), .pluginMissing)
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"invalid_pairing","message":"invalid pairing: relay url must use https","data":{"reason":"relay url must use https"}}"#),
                       .failed("invalid pairing: relay url must use https"))
        XCTAssertEqual(error(#"{"_tag":"RpcError","type":"configured","message":"set in OPENCODY_PAIRING","data":{"source":"env"}}"#), .failed("set in OPENCODY_PAIRING"))
    }

    /// `not_paired` now means the server forgot this device: re-pairing fixes it, no server config.
    func testNotPairedAsksToTurnPushOffAndOn() {
        for reply in [PluginReply.notPaired, .relayFailed(401), .relayFailed(410)] {
            XCTAssertTrue(reply.message.contains("Turn push off and on again"), reply.message)
            XCTAssertFalse(reply.message.contains("OPENCODY_PAIRING"), reply.message)
        }
    }

    /// Without a stored pairing there is nothing to register or remove, and no request is made.
    func testRegisterAndUnpairWithoutPairingDoNothing() async {
        let service = PushService()
        let server = ServerConnection(name: "lab", hostname: "127.0.0.1", port: 1, useHTTPS: false, username: "opencode", apiVersion: .v2)
        let reply = await service.registerOnServer(server)
        XCTAssertNil(reply)
        XCTAssertTrue(service.registering.isEmpty)
        await service.unpair(server: server.id, client: server.makeAPIClient())
        XCTAssertEqual(service.revision, 0)
    }

    // MARK: - Device token

    func testDeviceTokenTimesOut() async {
        let service = PushService()
        service.requestToken = {}
        service.tokenTimeout = .milliseconds(50)
        do {
            _ = try await service.deviceToken()
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? PushService.Failure, .noToken)
        }
    }

    func testDeviceTokenSurfacesRegistrationFailure() async {
        let service = PushService()
        service.requestToken = { service.didFailToRegister(URLError(.notConnectedToInternet)) }
        do {
            _ = try await service.deviceToken()
            XCTFail("expected a failure")
        } catch {
            guard case .registration(let reason) = error as? PushService.Failure else { return XCTFail("\(error)") }
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testDeviceTokenResolvesOnRegistration() async throws {
        let service = PushService()
        service.requestToken = { Task { await service.didRegister(deviceToken: Data([0xab, 0x01])) } }
        let token = try await service.deviceToken()
        XCTAssertEqual(token, "ab01")
    }
}
