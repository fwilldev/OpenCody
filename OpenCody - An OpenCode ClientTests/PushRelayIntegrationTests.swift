import XCTest
@testable import OpenCody___An_OpenCode_Client

/// The app's relay client against a local `opencody-push/relay` with a fake APNs.
/// Needs `OPENCODY_RELAY_URL` and `OPENCODY_FAKE_APNS_URL` (an endpoint returning the last
/// APNs payload as JSON); skipped otherwise. Never point it at the production relay.
final class PushRelayIntegrationTests: XCTestCase {

    func testRegisterPushRefreshAndUnpair() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["OPENCODY_RELAY_URL"], let apns = env["OPENCODY_FAKE_APNS_URL"].flatMap(URL.init(string:)) else {
            throw XCTSkip("OPENCODY_RELAY_URL / OPENCODY_FAKE_APNS_URL not set")
        }
        let relay = PushRelay(base: base)
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let device = try await relay.register(token: token, env: "sandbox")
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        let message = PushMessage(v: 1, type: "permission.asked", server: "local", directory: "/srv/app",
                                  sessionID: "ses_1", text: "bash: ls", requestID: "per_1", ts: 1)
        let ciphertext = try PushCrypto.seal(JSONEncoder().encode(message), key: key, deviceId: device.deviceId)
        try await relay.push(deviceId: device.deviceId, secret: device.secret, category: "OC_PERMISSION", ciphertext: ciphertext)

        let (data, _) = try await URLSession.shared.data(from: apns)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let aps = try XCTUnwrap(payload["aps"] as? [String: Any])
        XCTAssertEqual(aps["category"] as? String, "OC_PERMISSION")
        XCTAssertEqual(aps["mutable-content"] as? Int, 1)
        let envelope = try XCTUnwrap(PushEnvelope(userInfo: payload))
        XCTAssertEqual(try envelope.open(key: key), message)

        try await relay.update(deviceId: device.deviceId, secret: device.secret, token: token, env: "production")
        try await relay.delete(deviceId: device.deviceId, secret: device.secret)
        do {
            try await relay.update(deviceId: device.deviceId, secret: device.secret, token: token, env: "sandbox")
            XCTFail("unpaired device still accepted")
        } catch PushRelay.Failure.unauthorized {}
    }

    /// The app's server test against a real OpenCode 2 server running opencody-notify 0.3.0.
    /// Needs `OPENCODY_OC_URL`, `OPENCODY_OC_PASSWORD` and `OPENCODY_OC_DEVICE` (the deviceId of a
    /// pairing configured there, whose relay is unreachable); skipped otherwise.
    func testServerTestThroughPluginRPC() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["OPENCODY_OC_URL"], let password = env["OPENCODY_OC_PASSWORD"], let device = env["OPENCODY_OC_DEVICE"] else {
            throw XCTSkip("OPENCODY_OC_URL / OPENCODY_OC_PASSWORD / OPENCODY_OC_DEVICE not set")
        }
        let client = APIClient(baseURL: url, username: PairingAPI.username, password: password, apiVersion: .v2)
        let pairing = { (deviceId: String) in
            PushPairing(serverID: UUID(), relay: "http://127.0.0.1:1", deviceId: deviceId, secret: "s", key: Data(count: 32), token: "t", env: "sandbox")
        }
        let paired = await PushService.shared.sendServerTest(pairing(device), client: client)
        XCTAssertEqual(paired, .relayFailed(0))
        let other = await PushService.shared.sendServerTest(pairing("AAAAAAAAAAAAAAAAAAAAAA"), client: client)
        XCTAssertEqual(other, .notPaired)
    }

    /// Turning push on and off against a real OpenCode 2 server with opencody-notify 0.4.0 and the
    /// local relay: pair over RPC, the server's test push arrives, unpair, then `not_paired`.
    /// Needs `OPENCODY_OC_URL`, `OPENCODY_OC_PASSWORD`, `OPENCODY_RELAY_URL` (reachable from the
    /// server, loopback) and `OPENCODY_FAKE_APNS_URL`; skipped otherwise.
    func testAutoPairThroughPluginRPC() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["OPENCODY_OC_URL"], let password = env["OPENCODY_OC_PASSWORD"],
              let relayURL = env["OPENCODY_RELAY_URL"], let apns = env["OPENCODY_FAKE_APNS_URL"].flatMap(URL.init(string:)) else {
            throw XCTSkip("OPENCODY_OC_URL / OPENCODY_OC_PASSWORD / OPENCODY_RELAY_URL / OPENCODY_FAKE_APNS_URL not set")
        }
        let client = APIClient(baseURL: url, username: PairingAPI.username, password: password, apiVersion: .v2)
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let device = try await PushRelay(base: relayURL).register(token: token, env: "sandbox")
        let pairing = PushPairing(serverID: UUID(), relay: relayURL, deviceId: device.deviceId, secret: device.secret,
                                  key: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), token: token, env: "sandbox")
        let service = PushService.shared

        let before = await service.sendServerTest(pairing, client: client)
        XCTAssertEqual(before, .notPaired)
        guard case .sent = await service.register(pairing, client: client) else { return XCTFail("pair failed") }
        guard case .sent = await service.sendServerTest(pairing, client: client) else { return XCTFail("test after pair failed") }
        let (data, _) = try await URLSession.shared.data(from: apns)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let message = try XCTUnwrap(PushEnvelope(userInfo: payload)).open(key: pairing.key)
        XCTAssertEqual(message.type, "test")

        guard case .sent = await service.unregister(pairing, client: client) else { return XCTFail("unpair failed") }
        let after = await service.sendServerTest(pairing, client: client)
        XCTAssertEqual(after, .notPaired)
        try await PushRelay(base: relayURL).delete(deviceId: device.deviceId, secret: device.secret)
    }
}
