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
}
