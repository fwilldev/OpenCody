//
//  ClosedProjectsStore.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - ClosedProjectsStore

/// UserDefaults-backed persistence for "closed" (hidden) projects on the dashboard.
///
/// Projects are identified by their directory path and stored per-server so that
/// closing a project on one server doesn't affect another.
@Observable
final class ClosedProjectsStore {

    static let shared = ClosedProjectsStore()

    // MARK: - Storage Key

    private let storagePrefix = "closedProjects."

    // MARK: - In-Memory Cache

    /// Cached set of closed directory paths for the currently active server.
    /// Populated lazily via `load(for:)`.
    private(set) var closedDirectories: Set<String> = []

    /// The server ID currently loaded into memory.
    @ObservationIgnored private var loadedServerID: UUID?

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Load closed projects for a given server. Call when the active server changes.
    func load(for serverID: UUID) {
        loadedServerID = serverID
        closedDirectories = readFromDefaults(serverID: serverID)
    }

    /// Returns `true` if the project directory is closed for the given server.
    func isClosed(directory: String) -> Bool {
        closedDirectories.contains(directory)
    }

    /// Close (hide) a project directory.
    func close(directory: String, serverID: UUID) {
        ensureLoaded(serverID: serverID)
        closedDirectories.insert(directory)
        writeToDefaults(serverID: serverID)
    }

    /// Reopen a previously closed project directory.
    func reopen(directory: String, serverID: UUID) {
        ensureLoaded(serverID: serverID)
        closedDirectories.remove(directory)
        writeToDefaults(serverID: serverID)
    }

    /// Reopen a project if it's currently closed — called when creating a session
    /// for a project path that was previously closed.
    func reopenIfClosed(directory: String, serverID: UUID) {
        ensureLoaded(serverID: serverID)
        guard closedDirectories.contains(directory) else { return }
        reopen(directory: directory, serverID: serverID)
    }

    // MARK: - Private

    private func storageKey(for serverID: UUID) -> String {
        storagePrefix + serverID.uuidString
    }

    private func ensureLoaded(serverID: UUID) {
        if loadedServerID != serverID {
            load(for: serverID)
        }
    }

    private func readFromDefaults(serverID: UUID) -> Set<String> {
        let key = storageKey(for: serverID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(paths)
    }

    private func writeToDefaults(serverID: UUID) {
        let key = storageKey(for: serverID)
        let paths = Array(closedDirectories)
        guard let data = try? JSONEncoder().encode(paths) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
