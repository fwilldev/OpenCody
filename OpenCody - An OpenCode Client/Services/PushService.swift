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
    /// Each server plugin's last answer to `pair`, for the setup view; missing = not asked this launch.
    private(set) var serverReplies: [UUID: PluginReply] = [:]
    private(set) var registering: Set<UUID> = []

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
        await registerOnServers()
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

    /// Registers this device at the relay for `server` with a fresh key, replacing an older
    /// pairing, then on the server itself (SPEC §6.1 step 6).
    @discardableResult
    func pair(_ server: ServerConnection) async throws -> PushPairing {
        guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else {
            throw Failure.notAllowed
        }
        let token = try await deviceToken()
        let registration = try await PushRelay(base: Self.relayURL).register(token: token, env: Self.environment)
        await unpair(server: server.id, client: server.makeAPIClient())
        let pairing = PushPairing(
            serverID: server.id, relay: Self.relayURL, deviceId: registration.deviceId, secret: registration.secret,
            key: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }, token: token, env: Self.environment
        )
        try PushPairingStore.save(pairing)
        revision += 1
        await registerOnServer(server)
        return pairing
    }

    /// Removes the pairing on the server (best effort), at the relay (a 401 there means it is
    /// already gone) and here. `client` is nil when the server's credentials are gone.
    func unpair(server: UUID, client: APIClient?) async {
        guard let pairing = PushPairingStore.pairing(server: server) else { return }
        if let client { _ = await unregister(pairing, client: client) }
        try? await PushRelay(base: pairing.relay).delete(deviceId: pairing.deviceId, secret: pairing.secret)
        PushPairingStore.delete(deviceId: pairing.deviceId)
        serverReplies[server] = nil
        revision += 1
    }

    /// Hands this device's pairing to the server's plugin (0.4.0+). Idempotent, so it also
    /// repairs a server that lost its pairings file.
    @discardableResult
    func registerOnServer(_ server: ServerConnection) async -> PluginReply? {
        guard let pairing = PushPairingStore.pairing(server: server.id), !pairing.broken,
              registering.insert(server.id).inserted else { return nil }
        defer { registering.remove(server.id) }
        let reply = await register(pairing, client: server.makeAPIClient())
        serverReplies[server.id] = reply
        return reply
    }

    func register(_ pairing: PushPairing, client: APIClient) async -> PluginReply {
        await callPlugin("pair", ["pairing": pairing.pairingString], client: client)
    }

    func unregister(_ pairing: PushPairing, client: APIClient) async -> PluginReply {
        await callPlugin("unpair", ["deviceId": pairing.deviceId], client: client)
    }

    /// Once per launch, after the token refresh: re-registers every paired server not asked yet.
    private func registerOnServers() async {
        for server in ServerStore.shared.load() where server.apiVersion == .v2 && serverReplies[server.id] == nil {
            await registerOnServer(server)
        }
    }

    /// Asks the server's `opencody-notify` plugin to push to this device: the real path
    /// server → relay → APNs → device (SPEC §6.1 step 7).
    func sendServerTest(_ pairing: PushPairing, client: APIClient) async -> PluginReply {
        await callPlugin("test", ["deviceId": pairing.deviceId], client: client)
    }

    /// `POST /api/rpc/opencody-notify/<method>` at the server's default location.
    private func callPlugin(_ method: String, _ input: [String: String], client: APIClient) async -> PluginReply {
        let endpoint = APIEndpoint.v2("/api/rpc/opencody-notify/\(method)", method: .POST, json: ["input": input], timeout: 20)
        do {
            return PluginReply(success: try await client.requestData(endpoint))
        } catch OpenCodeError.validation(400, let body) {
            let result = PluginReply(rpcError: Data(body.utf8))
            guard result == .pluginMissing else { return result }
            // Not loaded, or too old for this method: ask which plugins run.
            let plugins = try? await client.requestData(.get("/api/plugin"))
            return plugins.map(PluginReply.init(plugins:)) ?? result
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

/// Answer of the server's `opencody-notify` plugin to an RPC (`pair`, `unpair`, `test`).
nonisolated enum PluginReply: Equatable {
    /// `server` is the plugin's label for its server.
    case sent(server: String)
    /// The plugin runs, but doesn't know this device.
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

    /// `GET /api/plugin` after `rpc.unavailable`/`rpc.method_not_found`: listed means loaded but too old.
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
            "The plugin runs on your server, but doesn't know this device. Turn push off and on again."
        case .relayFailed(0):
            "Your server couldn't reach the push relay. It needs outbound HTTPS to \(PushService.relayURL)."
        case .relayFailed(401), .relayFailed(410):
            "The relay no longer knows this device. Turn push off and on again."
        case .relayFailed(429):
            "Too many notifications. Try again in a minute."
        case .relayFailed(let status):
            "The push relay answered \(status) to your server."
        case .pluginOutdated:
            "Your server runs an older opencody-notify. Update the plugin to 0.4.0, then restart OpenCode."
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
