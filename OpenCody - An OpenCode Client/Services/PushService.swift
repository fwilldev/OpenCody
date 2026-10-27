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
            case .unauthorized, .unregistered: "The relay no longer knows this iPhone. Pair again."
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

/// Pairs this iPhone with OpenCode 2 servers for push (SPEC §6.1–6.3).
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

    /// Registers this iPhone at the relay for `server` with a fresh key; replaces an older pairing.
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

    /// Pushes a self-encrypted message through relay, APNs and the extension, without the server (§6.1.7).
    func sendTest(_ pairing: PushPairing, serverName: String) async throws {
        let message = PushMessage(
            v: 1, type: "session.finished", server: serverName, sessionID: "",
            title: "OpenCody", text: "Test notification. Push works for this server.",
            ts: (Date().timeIntervalSince1970 * 1000).rounded()
        )
        let ciphertext = try PushCrypto.seal(JSONEncoder().encode(message), key: pairing.key, deviceId: pairing.deviceId)
        try await PushRelay(base: pairing.relay).push(
            deviceId: pairing.deviceId, secret: pairing.secret, category: NotificationCategory.session, ciphertext: ciphertext
        )
    }
}

/// Whether a server can reach this iPhone by push.
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
