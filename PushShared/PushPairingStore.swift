import Foundation
import Security

/// One push registration of this iPhone for one OpenCode server (§6.1).
nonisolated struct PushPairing: Codable, Equatable, Sendable {
    var serverID: UUID
    var relay: String
    var deviceId: String
    var secret: String
    var key: Data
    /// APNs token and environment last sent to the relay.
    var token: String
    var env: String
    var broken = false

    var pairingString: String {
        PairingString.encode(relay: relay, deviceId: deviceId, secret: secret, key: key)
    }
}

/// Pairings live in a keychain group shared with the Notification Service Extension,
/// readable after first unlock so pushes decrypt while the phone is locked.
nonisolated enum PushPairingStore {
    static let accessGroup = "Q738AAV584.wss.OpenCody.shared"
    private static let service = "com.opencody.push"

    private static func query(_ deviceId: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        if let deviceId { query[kSecAttrAccount as String] = deviceId }
        return query
    }

    static func all() -> [PushPairing] {
        var search = query()
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let items = result as? [Data] else { return [] }
        return items.compactMap { try? JSONDecoder().decode(PushPairing.self, from: $0) }
    }

    static func pairing(deviceId: String) -> PushPairing? {
        all().first { $0.deviceId == deviceId }
    }

    static func pairing(server: UUID) -> PushPairing? {
        all().first { $0.serverID == server }
    }

    static func save(_ pairing: PushPairing) throws {
        let data = try JSONEncoder().encode(pairing)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(pairing.deviceId) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(pairing.deviceId).merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    }

    static func delete(deviceId: String) {
        SecItemDelete(query(deviceId) as CFDictionary)
    }

    struct KeychainFailure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Couldn't save to the keychain (\(status))." }
    }
}
