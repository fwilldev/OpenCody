import CryptoKit
import UIKit
import UserNotifications

/// The OpenCody push relay's HTTP API (SPEC §2).
nonisolated struct PushRelay: Sendable {
    let base: String
    var session: URLSession = .shared

    enum Failure: LocalizedError, Equatable {
        /// Unknown device or wrong secret: the pairing is gone on the relay.
        case unauthorized
        case unregistered
        case status(Int, String)

        var errorDescription: String? {
            switch self {
            case .unauthorized, .unregistered: "The relay no longer knows this device. Pair again."
            case .status(429, _): "Too many requests. Try again in a minute."
            case .status(let code, let reason): "The push relay answered \(code)\(reason.isEmpty ? "" : ": \(reason)")."
            }
        }
    }

    func register(token: String, env: String) async throws -> (deviceId: String, secret: String) {
        let data = try await send("POST", "/v1/devices", body: ["token": token, "env": env])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let deviceId = object?["deviceId"] as? String, let secret = object?["secret"] as? String else {
            throw Failure.status(201, "no device id")
        }
        return (deviceId, secret)
    }

    func update(deviceId: String, secret: String, token: String, env: String) async throws {
        _ = try await send("PUT", "/v1/devices/\(deviceId)", secret: secret, body: ["token": token, "env": env])
    }

    func delete(deviceId: String, secret: String) async throws {
        _ = try await send("DELETE", "/v1/devices/\(deviceId)", secret: secret)
    }

    func push(deviceId: String, secret: String, category: String, ciphertext: String) async throws {
        _ = try await send("POST", "/v1/push", secret: secret,
                           body: ["deviceId": deviceId, "category": category, "ciphertext": ciphertext])
    }

    private func send(_ method: String, _ path: String, secret: String? = nil, body: [String: String]? = nil) async throws -> Data {
        guard let url = URL(string: base + path) else { throw Failure.status(0, "invalid relay URL") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        if let secret { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299: return data
        case 401: throw Failure.unauthorized
        case 410: throw Failure.unregistered
        default:
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Failure.status(status, reason ?? "")
        }
    }
}

/// Pairs this device with OpenCode 2 servers for push (SPEC §6.1–6.3).
@Observable
final class PushService {
    static let shared = PushService()

    static let relayURL = "https://push.willsoftwaresolutions.de"
    /// Xcode debug builds get sandbox tokens; TestFlight and App Store builds production ones.
    #if DEBUG
    static let environment = "sandbox"
    #else
    static let environment = "production"
    #endif

    /// Changes whenever a pairing does, so views re-read the keychain.
    private(set) var revision = 0

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var tokenWaiters: [UUID: CheckedContinuation<String, Error>] = [:]
    @ObservationIgnored var tokenTimeout: Duration = .seconds(10)
    @ObservationIgnored var requestToken: () -> Void = { UIApplication.shared.registerForRemoteNotifications() }

    enum Failure: LocalizedError, Equatable {
        case notAllowed, noToken
        case registration(String)

        var errorDescription: String? {
            switch self {
            case .notAllowed: "Notifications are off for OpenCody. Turn them on in the Settings app."
            case .noToken: "iOS didn't hand out a push token within 10 seconds. Check the internet connection and try again."
            case .registration(let reason): "iOS couldn't register for push: \(reason)"
            }
        }
    }

    // MARK: - Device token

    /// Asks iOS for the token on launch, which refreshes every pairing.
    func registerIfPaired() {
        guard !PushPairingStore.all().isEmpty else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        tokenWaiters.values.forEach { $0.resume(returning: hex) }
        tokenWaiters = [:]
        await refresh(token: hex)
    }

    func didFailToRegister(_ error: Error) {
        tokenWaiters.values.forEach { $0.resume(throwing: Failure.registration(error.localizedDescription)) }
        tokenWaiters = [:]
    }

    func deviceToken() async throws -> String {
        if let token { return token }
        let id = UUID()
        Task {
            try? await Task.sleep(for: tokenTimeout)
            tokenWaiters.removeValue(forKey: id)?.resume(throwing: Failure.noToken)
        }
        return try await withCheckedThrowingContinuation { continuation in
            tokenWaiters[id] = continuation
            requestToken()
        }
    }

    /// Sends the current token to the relay for every pairing; a 401 marks the pairing broken.
    private func refresh(token: String) async {
        for var pairing in PushPairingStore.all() where !pairing.broken {
            do {
                try await PushRelay(base: pairing.relay).update(
                    deviceId: pairing.deviceId, secret: pairing.secret, token: token, env: Self.environment
                )
                pairing.token = token
                pairing.env = Self.environment
            } catch PushRelay.Failure.unauthorized {
                pairing.broken = true
            } catch {
                continue
            }
            try? PushPairingStore.save(pairing)
        }
        revision += 1
    }

    // MARK: - Pairing

    func pairing(for server: UUID) -> PushPairing? {
        _ = revision
        return PushPairingStore.pairing(server: server)
    }

    /// Registers this device at the relay for `server` with a fresh key; replaces an older pairing.
    @discardableResult
    func pair(_ server: ServerConnection) async throws -> PushPairing {
        guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else {
            throw Failure.notAllowed
        }
        let token = try await deviceToken()
        let registration = try await PushRelay(base: Self.relayURL).register(token: token, env: Self.environment)
        await unpair(server: server.id)
        let pairing = PushPairing(
            serverID: server.id, relay: Self.relayURL, deviceId: registration.deviceId, secret: registration.secret,
            key: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }, token: token, env: Self.environment
        )
        try PushPairingStore.save(pairing)
        revision += 1
        return pairing
    }

    /// Removes the pairing here and at the relay (a 401 there means it is already gone).
    func unpair(server: UUID) async {
        guard let pairing = PushPairingStore.pairing(server: server) else { return }
        try? await PushRelay(base: pairing.relay).delete(deviceId: pairing.deviceId, secret: pairing.secret)
        PushPairingStore.delete(deviceId: pairing.deviceId)
        revision += 1
    }

    /// Asks the server's `opencody-notify` plugin to push to this device: the real path
    /// server → relay → APNs → device (SPEC §6.1 step 7).
    func sendServerTest(_ pairing: PushPairing, client: APIClient) async -> ServerPushTest {
        let endpoint = APIEndpoint.v2("/api/rpc/opencody-notify/test", method: .POST,
                                      json: ["input": ["deviceId": pairing.deviceId]], timeout: 20)
        do {
            return ServerPushTest(success: try await client.requestData(endpoint))
        } catch OpenCodeError.validation(400, let body) {
            let result = ServerPushTest(rpcError: Data(body.utf8))
            guard result == .pluginMissing else { return result }
            // Not loaded: 0.2.0 has no test route, so ask which plugins run.
            let plugins = try? await client.requestData(.get("/api/plugin"))
            return plugins.map(ServerPushTest.init(plugins:)) ?? result
        } catch OpenCodeError.notFound {
            return .serverTooOld
        } catch let error as URLError {
            return .offline(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Pushes a self-encrypted message through relay, APNs and the extension, without the server.
    func sendRelayTest(_ pairing: PushPairing, serverName: String) async throws {
        let message = PushMessage(
            v: 1, type: "test", server: serverName, sessionID: "",
            title: "OpenCody", text: "Relay test. The relay and this device work; your server wasn't involved.",
            ts: (Date().timeIntervalSince1970 * 1000).rounded()
        )
        let ciphertext = try PushCrypto.seal(JSONEncoder().encode(message), key: pairing.key, deviceId: pairing.deviceId)
        try await PushRelay(base: pairing.relay).push(
            deviceId: pairing.deviceId, secret: pairing.secret, category: NotificationCategory.session, ciphertext: ciphertext
        )
    }
}

/// Result of asking the server to send a test push (plugin RPC `opencody-notify.test`).
nonisolated enum ServerPushTest: Equatable {
    case sent(server: String)
    /// The plugin runs, but this device's pairing string isn't configured on the server.
    case notPaired
    /// The relay refused the server's push; `0` means the server couldn't reach it.
    case relayFailed(Int)
    case pluginOutdated
    case pluginMissing
    case pluginFailed(String)
    /// No plugin RPC route: OpenCode older than 2.1.
    case serverTooOld
    case offline(String)
    case failed(String)

    /// `200 {"output": {"server": …}}`; a 2.x server without the route answers with its web app.
    init(success data: Data) {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let output = object?["output"] as? [String: Any] else { self = .serverTooOld; return }
        self = .sent(server: output["server"] as? String ?? "")
    }

    /// `400 {"_tag": "RpcError", "type": …, "data": …}`.
    init(rpcError data: Data) {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = object?["message"] as? String ?? String(decoding: data, as: UTF8.self)
        switch object?["type"] as? String {
        case "not_paired": self = .notPaired
        case "relay_failed": self = .relayFailed((object?["data"] as? [String: Any])?["status"] as? Int ?? 0)
        case "rpc.unavailable", "rpc.method_not_found": self = .pluginMissing
        default: self = .failed(message)
        }
    }

    /// `GET /api/plugin` after `rpc.unavailable`: listed means loaded but older than 0.3.0.
    init(plugins data: Data) {
        let list = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        guard let plugin = list.first(where: { $0["id"] as? String == "opencody-notify" }) else { self = .pluginMissing; return }
        let state = plugin["state"] as? [String: Any]
        self = state?["status"] as? String == "failed" ? .pluginFailed(state?["error"] as? String ?? "") : .pluginOutdated
    }

    var message: String {
        switch self {
        case .sent(let server):
            "Sent by \(server.isEmpty ? "your server" : "“\(server)”"). It should arrive on this device in a few seconds. If it doesn't, try Test Relay Only."
        case .notPaired:
            "The plugin runs on your server, but without this device's pairing string. Add it to OPENCODY_PAIRING and restart OpenCode."
        case .relayFailed(0):
            "Your server couldn't reach the push relay. It needs outbound HTTPS to \(PushService.relayURL)."
        case .relayFailed(401), .relayFailed(410):
            "The relay no longer knows this device. Pair again and replace the pairing string on the server."
        case .relayFailed(429):
            "Too many notifications. Try again in a minute."
        case .relayFailed(let status):
            "The push relay answered \(status) to your server."
        case .pluginOutdated:
            "Your server runs an older opencody-notify. Update the plugin to 0.3.0 or later for the server test, then restart OpenCode."
        case .pluginMissing:
            "The opencody-notify plugin isn't running on your server. Follow Set Up the Server and install it globally with: opencode plugin add opencody-notify"
        case .pluginFailed(let error):
            "The opencody-notify plugin failed to load on your server\(error.isEmpty ? "" : ": \(error)")."
        case .serverTooOld:
            "The server test needs OpenCode 2.1 or later on your server."
        case .offline(let reason):
            "Can't reach your server: \(reason)"
        case .failed(let reason):
            reason
        }
    }
}

/// Whether a server can reach this device by push.
nonisolated enum PushStatus: Equatable {
    case unsupported, off, paired, broken

    init(apiVersion: ServerAPIVersion, pairing: PushPairing?) {
        self = if apiVersion != .v2 { .unsupported }
            else if let pairing { pairing.broken ? .broken : .paired }
            else { .off }
    }

    var label: String {
        switch self {
        case .unsupported: "Needs OpenCode 2"
        case .off: "Not paired"
        case .paired: "Paired"
        case .broken: "Pairing stopped working"
        }
    }
}

/// Receives the APNs device token, which SwiftUI has no hook for.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushService.shared.registerIfPaired()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushService.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushService.shared.didFailToRegister(error)
    }
}
