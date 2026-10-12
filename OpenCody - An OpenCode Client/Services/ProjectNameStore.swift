import Foundation

// MARK: - ProjectNameStore

/// Custom project names kept on the device, per server and project directory.
///
/// Used for directories the server cannot name itself: folders outside a git
/// repository all share the server's single `global` project, so renaming that
/// project server-side would rename every one of them.
struct ProjectNameStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ serverID: UUID) -> String { "projectNames." + serverID.uuidString }

    /// Directory → custom name for one server.
    func names(for serverID: UUID) -> [String: String] {
        defaults.dictionary(forKey: key(serverID)) as? [String: String] ?? [:]
    }

    /// Store `name` for `directory`; an empty or `nil` name removes it.
    func setName(_ name: String?, directory: String, serverID: UUID) {
        var all = names(for: serverID)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        all[directory] = trimmed.isEmpty ? nil : trimmed
        defaults.set(all, forKey: key(serverID))
    }
}
