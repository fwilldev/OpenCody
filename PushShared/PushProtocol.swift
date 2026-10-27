import CryptoKit
import Foundation
import UserNotifications

// OpenCody push protocol v1, shared by the app and the Notification Service Extension.
// Spec: opencody-push/SPEC.md.

nonisolated enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var value = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value)
    }
}

/// The single-line credential the user puts into the server plugin (§3).
nonisolated enum PairingString {
    struct Fields: Codable, Equatable, Sendable {
        var v = 1
        var relay: String
        var deviceId: String
        var secret: String
        var key: String
    }

    static func encode(relay: String, deviceId: String, secret: String, key: Data) -> String {
        let fields = Fields(relay: trimmed(relay), deviceId: deviceId, secret: secret, key: Base64URL.encode(key))
        return Base64URL.encode((try? JSONEncoder().encode(fields)) ?? Data())
    }

    static func decode(_ string: String) -> Fields? {
        guard let data = Base64URL.decode(string.trimmingCharacters(in: .whitespacesAndNewlines)),
              var fields = try? JSONDecoder().decode(Fields.self, from: data),
              fields.v == 1, Base64URL.decode(fields.key)?.count == 32
        else { return nil }
        fields.relay = trimmed(fields.relay)
        return fields
    }

    private static func trimmed(_ relay: String) -> String {
        var relay = relay
        while relay.hasSuffix("/") { relay.removeLast() }
        return relay
    }
}

/// AES-256-GCM; ciphertext is base64 of nonce ‖ ciphertext ‖ tag (§4).
nonisolated enum PushCrypto {
    enum Failure: Error { case malformed }

    static func aad(_ deviceId: String) -> Data { Data("opencody-push:v1:\(deviceId)".utf8) }

    static func seal(_ plaintext: Data, key: Data, deviceId: String, nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> String {
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), nonce: nonce, authenticating: aad(deviceId))
        guard let combined = box.combined else { throw Failure.malformed }
        return combined.base64EncodedString()
    }

    static func open(_ ciphertext: String, key: Data, deviceId: String) throws -> Data {
        guard let data = Data(base64Encoded: ciphertext) else { throw Failure.malformed }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: key), authenticating: aad(deviceId))
    }
}

/// The `ocp` object of an APNs payload (§2.6).
nonisolated struct PushEnvelope: Sendable {
    let deviceId: String
    let ciphertext: String

    init?(userInfo: [AnyHashable: Any]) {
        guard let ocp = userInfo["ocp"] as? [String: Any], ocp["v"] as? Int == 1,
              let deviceId = ocp["d"] as? String, let ciphertext = ocp["c"] as? String
        else { return nil }
        self.deviceId = deviceId
        self.ciphertext = ciphertext
    }

    func open(key: Data) throws -> PushMessage {
        try PushMessage.decode(PushCrypto.open(ciphertext, key: key, deviceId: deviceId))
    }
}

/// Decrypted message (§5).
nonisolated struct PushMessage: Codable, Equatable, Sendable {
    var v: Int
    var type: String
    var server: String
    var directory: String?
    var sessionID: String
    var rootSessionID: String?
    var title: String?
    var text: String
    var requestID: String?
    /// Dedupe key from plugin 0.2.0 on (§5.1).
    var key: String?
    var ts: Double

    static func decode(_ data: Data) throws -> PushMessage {
        try JSONDecoder().decode(PushMessage.self, from: data)
    }

    /// Unknown versions and messages older than a day (a replaying relay) stay generic (§6.4).
    func isDeliverable(now: Date = Date()) -> Bool {
        v == 1 && now.timeIntervalSince1970 * 1000 - ts < 24 * 3600 * 1000
    }

    /// The session to open; requests from subagents are answered in their parent.
    var openSessionID: String { rootSessionID ?? sessionID }

    /// Presentation from §6.4, plus the `userInfo` keys for deep links and actions.
    func apply(to content: UNMutableNotificationContent, serverID: UUID) {
        content.title = title ?? "OpenCode"
        let folder = directory.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        content.subtitle = [server, folder].compactMap { $0 }.joined(separator: " · ")
        content.body = switch type {
        case "session.failed": "Failed: \(text)"
        case "permission.asked": "Permission needed: \(text)"
        case "form.asked": "Question: \(text)"
        default: text
        }
        content.threadIdentifier = openSessionID
        content.categoryIdentifier = NotificationCategory.forType(type)

        var info = content.userInfo
        info["serverID"] = serverID.uuidString
        if !openSessionID.isEmpty { info["sessionID"] = openSessionID }
        info["replySessionID"] = sessionID
        info["directory"] = directory
        info["requestID"] = requestID
        info["dedupe"] = AlertKey.forPush(self)
        info["opencody"] = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) ?? [:]
        content.userInfo = info
    }
}

/// Category IDs, fixed by the relay (§6.5).
nonisolated enum NotificationCategory {
    static let session = "OC_SESSION"
    static let permission = "OC_PERMISSION"
    static let form = "OC_FORM"

    static func forType(_ type: String) -> String {
        switch type {
        case "permission.asked": permission
        case "form.asked": form
        default: session
        }
    }
}

/// Dedupe keys of pushes, stored in `userInfo["dedupe"]`:
/// `req:<id>` for requests, `<sessionID>@<idle ms>` for finished or failed runs.
/// Pushes without a `key` get `~<sessionID>@<event ms>`, which only matches within a time window.
nonisolated enum AlertKey {
    /// The event time of old payloads lies close to, but not exactly on, the session's idle time.
    /// ponytail: a second run of the same session ending within this window counts as a duplicate.
    static let runWindow: Double = 10_000

    static func forPush(_ message: PushMessage) -> String {
        if let key = message.key { return key }
        if let requestID = message.requestID { return "req:\(requestID)" }
        return "~\(message.sessionID)@\(Int64(message.ts))"
    }

    static func isDuplicate(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.hasPrefix("~") || b.hasPrefix("~"), let run1 = run(a), let run2 = run(b) else { return false }
        return run1.session == run2.session && abs(run1.time - run2.time) < runWindow
    }

    private static func run(_ key: String) -> (session: Substring, time: Double)? {
        let key = key.hasPrefix("~") ? key.dropFirst() : Substring(key)
        guard !key.hasPrefix("req:"), let at = key.lastIndex(of: "@"), let time = Double(key[key.index(after: at)...]) else { return nil }
        return (key[..<at], time)
    }
}
