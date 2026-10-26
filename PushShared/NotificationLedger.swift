import Foundation

/// Remembers what was already notified across launches, so live events, catch-up,
/// background refresh and delivered pushes never announce the same alert twice.
/// Lives in the App Group, where the Notification Service Extension records pushes.
/// ponytail: app and extension may write at the same moment and lose one key; worst case is one extra alert.
nonisolated final class NotificationLedger {
    static let appGroup = "group.wss.OpenCody"
    private static let keysKey = "notification.ledger"
    private static let baselinesKey = "notification.ledger.baselines"
    private static let migratedKey = "notification.ledger.migrated"

    /// The App Group store, filled once from the app's own defaults that held the ledger before 1.10.
    nonisolated(unsafe) static let shared: UserDefaults = {
        guard let group = UserDefaults(suiteName: appGroup) else { return .standard }
        migrate(from: .standard, to: group)
        return group
    }()

    private let defaults: UserDefaults
    private let capacity: Int

    init(defaults: UserDefaults = NotificationLedger.shared, capacity: Int = 500) {
        self.defaults = defaults
        self.capacity = capacity
    }

    static func migrate(from legacy: UserDefaults, to group: UserDefaults) {
        guard !group.bool(forKey: migratedKey) else { return }
        for key in [keysKey, baselinesKey] {
            let old = legacy.stringArray(forKey: key) ?? []
            let current = group.stringArray(forKey: key) ?? []
            group.set(old + current.filter { !old.contains($0) }, forKey: key)
            legacy.removeObject(forKey: key)
        }
        group.set(true, forKey: migratedKey)
    }

    /// Records `key`; `false` if it, or an old push's key for the same run, was already there.
    @discardableResult
    func insert(_ key: String) -> Bool {
        var keys = defaults.stringArray(forKey: Self.keysKey) ?? []
        guard !keys.contains(where: { AlertKey.isDuplicate($0, key) }) else { return false }
        keys.append(key)
        keys.removeFirst(max(0, keys.count - capacity))
        defaults.set(keys, forKey: Self.keysKey)
        return true
    }

    /// `true` only the first time a server is caught up.
    func markBaseline(_ server: UUID) -> Bool {
        var servers = defaults.stringArray(forKey: Self.baselinesKey) ?? []
        guard !servers.contains(server.uuidString) else { return false }
        servers.append(server.uuidString)
        defaults.set(servers, forKey: Self.baselinesKey)
        return true
    }
}
