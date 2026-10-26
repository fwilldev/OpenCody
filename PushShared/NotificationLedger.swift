import Foundation

/// Remembers which pushes were already shown, so a re-delivered push stays quiet.
/// Lives in the App Group, where the Notification Service Extension records pushes.
/// ponytail: two extension processes may write at the same moment and lose one key; worst case is one extra alert.
nonisolated final class NotificationLedger {
    static let appGroup = "group.wss.OpenCody"
    private static let keysKey = "notification.ledger"

    nonisolated(unsafe) static let shared = UserDefaults(suiteName: appGroup) ?? .standard

    private let defaults: UserDefaults
    private let capacity: Int

    init(defaults: UserDefaults = NotificationLedger.shared, capacity: Int = 500) {
        self.defaults = defaults
        self.capacity = capacity
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
}
