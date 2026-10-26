//
//  DashboardViewModel.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import Foundation

// MARK: - DashboardViewModel

/// Manages session list state, SSE event observation, and session CRUD for the dashboard.
@Observable
final class DashboardViewModel {

    // MARK: - Observable State

    var sessions: [Session] = []
    var isLoading: Bool = false
    var error: String? = nil
    var statusMap: [String: SessionStatus] = [:]
    var showArchived: Bool = false
    var showClosedProjects: Bool = false
    /// Server-side projects, used to resolve and set project names.
    var projects: [Project] = []
    /// Device-local project names (directory → name) for the active server.
    var customProjectNames: [String: String] = [:]

    // MARK: - Dependencies

    @ObservationIgnored private let connectionManager: ConnectionManager
    @ObservationIgnored private let closedProjectsStore = ClosedProjectsStore.shared
    @ObservationIgnored private let projectNameStore = ProjectNameStore()

    // MARK: - Init

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
    }

    // MARK: - Closed Projects

    /// Load closed-projects state for the active server.
    func loadClosedProjects() {
        guard let serverID = connectionManager.activeServerID else { return }
        closedProjectsStore.load(for: serverID)
        customProjectNames = projectNameStore.names(for: serverID)
    }

    /// Whether a given directory is currently closed.
    func isProjectClosed(directory: String) -> Bool {
        closedProjectsStore.isClosed(directory: directory)
    }

    /// Close a project by hiding all sessions with the given directory.
    func closeProject(directory: String) {
        guard let serverID = connectionManager.activeServerID else { return }
        closedProjectsStore.close(directory: directory, serverID: serverID)
    }

    /// Reopen a previously closed project.
    func reopenProject(directory: String) {
        guard let serverID = connectionManager.activeServerID else { return }
        closedProjectsStore.reopen(directory: directory, serverID: serverID)
    }

    /// The set of currently closed directory paths (for filtering).
    var closedDirectories: Set<String> {
        closedProjectsStore.closedDirectories
    }

    // MARK: - Projects

    /// Visible sessions grouped by project directory, sorted by display name.
    var projectGroups: [ProjectGroup] {
        let closed = closedDirectories
        return Dictionary(grouping: activeSessions, by: \.directory)
            .map { directory, sessions in
                ProjectGroup(
                    directory: directory,
                    name: projectName(for: directory),
                    hasCustomName: hasCustomName(directory: directory),
                    sessions: sessions.sorted { $0.time.updated > $1.time.updated }
                )
            }
            .filter { showClosedProjects || !closed.contains($0.directory) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The server project that owns exactly this directory, if it can be renamed server-side.
    ///
    /// Non-git folders all share the server's `global` project, and a git project's
    /// name applies to every checkout, so only a project's primary worktree qualifies.
    func serverProject(for directory: String) -> Project? {
        projects.first { $0.id != "global" && $0.worktree == directory }
    }

    /// Display name for a project directory: local name, then server name, then folder name.
    func projectName(for directory: String) -> String {
        if let custom = customProjectNames[directory] { return custom }
        if let name = serverProject(for: directory)?.name, !name.isEmpty { return name }
        let folder = (directory as NSString).lastPathComponent
        return folder.isEmpty ? directory : folder
    }

    func hasCustomName(directory: String) -> Bool {
        customProjectNames[directory] != nil || !(serverProject(for: directory)?.name ?? "").isEmpty
    }

    /// Rename a project, or reset it to its folder name when `name` is empty.
    ///
    /// Uses the server's project name where the server can store one for just this
    /// directory, otherwise a device-local name. Applied optimistically.
    func renameProject(directory: String, to name: String) async throws {
        guard let serverID = connectionManager.activeServerID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let project = serverProject(for: directory), let client = connectionManager.activeAPIClient else {
            projectNameStore.setName(trimmed, directory: directory, serverID: serverID)
            customProjectNames = projectNameStore.names(for: serverID)
            return
        }

        // A server name supersedes any older local one.
        projectNameStore.setName(nil, directory: directory, serverID: serverID)
        customProjectNames = projectNameStore.names(for: serverID)
        let previous = projects
        replaceProject(project.renamed(trimmed))
        do {
            let updated = try await FileAPI(client: client).updateProject(projectID: project.id, name: trimmed)
            replaceProject(updated)
        } catch {
            projects = previous
            throw error
        }
    }

    private func replaceProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }
    }

    /// Load server projects. Failures only cost the server-side names.
    func loadProjects() async {
        guard let client = connectionManager.activeAPIClient else { return }
        if let loaded = try? await FileAPI(client: client).listProjects() {
            projects = loaded
        }
    }

    // MARK: - Filtered Sessions

    /// Sessions filtered by archive status.
    /// When `showArchived` is false (default), archived sessions are hidden.
    var activeSessions: [Session] {
        if showArchived {
            return sessions
        }
        return sessions.filter { $0.time.archived == nil }
    }

    // MARK: - Session Loading

    /// Fetch all sessions from the active server.
    func loadSessions() async {
        guard let client = connectionManager.activeAPIClient else {
            // No server connected — empty state handles this, no error needed
            sessions = []
            return
        }

        // Don't attempt API calls when the server is offline — the offline UI
        // handles this state; hitting the network would only produce repeated errors.
        if let id = connectionManager.activeServerID,
           connectionManager.connectionState(for: id) == .offline {
            return
        }

        isLoading = true
        error = nil

        do {
            // Deliberately unscoped: the dashboard lists sessions across every project.
            let api = SessionAPI(client: client)
            let fetched = try await api.list()
            sessions = fetched.sorted { $0.time.updated > $1.time.updated }
        } catch is CancellationError {
            // Task was cancelled by SwiftUI lifecycle (e.g. pull-to-refresh interrupted)
            // — not a real error, don't surface to the user.
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession request was cancelled — same as above.
            return
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    /// Fetch status of all sessions from the active server.
    func loadStatuses() async {
        guard let client = connectionManager.activeAPIClient else { return }

        // Don't attempt API calls when the server is offline.
        if let id = connectionManager.activeServerID,
           connectionManager.connectionState(for: id) == .offline {
            return
        }

        do {
            let api = SessionAPI(client: client)
            statusMap = try await api.status()
        } catch is CancellationError {
            // Cancelled — ignore silently.
        } catch {
            // Status loading is non-critical — silently ignore
        }
    }

    // MARK: - Session CRUD

    /// Create a new session in the project matching `path`.
    /// The default agent and model are applied automatically when the session chat is opened.
    func createSession(path: String) async throws -> Session {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let normalizedPath = ServerPath.normalized(path)

        // Auto-reopen if the project was previously closed
        if let serverID = connectionManager.activeServerID {
            closedProjectsStore.reopenIfClosed(directory: normalizedPath, serverID: serverID)
        }

        let api = SessionAPI(client: client, directory: normalizedPath)
        let session = try await api.create()

        // Insert the new session immediately instead of relying on loadSessions(),
        // which can be cancelled by SwiftUI task management and cause spurious errors.
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.insert(session, at: 0)
        }

        return session
    }

    /// Delete a session by ID.
    /// The project directory of a loaded session.
    ///
    /// Per-session routes must be scoped to the session's own project, which these
    /// id-only entry points would otherwise not know.
    private func directory(of sessionID: String) -> String? {
        sessions.first { $0.id == sessionID }?.directory
    }

    func deleteSession(id: String) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let api = SessionAPI(client: client, directory: directory(of: id))
        try await api.delete(id: id)
        sessions.removeAll { $0.id == id }
        statusMap.removeValue(forKey: id)
    }

    /// Archive a session.
    func archiveSession(id: String) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let api = SessionAPI(client: client, directory: directory(of: id))
        let updated = try await api.update(id: id, setArchived: true)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = updated
        }
    }

    /// Unarchive a session.
    func unarchiveSession(id: String) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let api = SessionAPI(client: client, directory: directory(of: id))
        let updated = try await api.update(id: id, setArchived: false)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = updated
        }
    }

    /// Rename a session, showing the new title immediately and reverting if the server refuses.
    @discardableResult
    func renameSession(_ session: Session, to title: String) async throws -> Session {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }
        replaceSession(session.retitled(title))
        do {
            let updated = try await SessionAPI(client: client, directory: session.directory).update(id: session.id, title: title)
            replaceSession(updated)
            return updated
        } catch {
            replaceSession(session)
            throw error
        }
    }

    private func replaceSession(_ session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    // MARK: - SSE Event Observation

    @ObservationIgnored private var eventToken: UUID?
    @ObservationIgnored private var refreshToken: UUID?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastSSEEventAt: Date?

    /// Views showing this model. A resize can show the new layout before the old one
    /// disappears, so events stop only when the last of them has stopped observing.
    @ObservationIgnored private var observerCount = 0

    /// Subscribe to SSE events for live session updates.
    func startObservingEvents() {
        observerCount += 1
        guard observerCount == 1 else { return }
        eventToken = connectionManager.subscribeToEvents { [weak self] event in
            self?.handleEvent(event)
        }
        refreshToken = connectionManager.subscribeToRefresh { [weak self] in
            guard let self else { return }
            Task {
                await self.loadSessions()
                await self.loadStatuses()
            }
        }
        startStatusPolling()
    }

    /// Unsubscribe from SSE events.
    func stopObservingEvents() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }
        if let t = eventToken { connectionManager.unsubscribeFromEvents(token: t) }
        if let t = refreshToken { connectionManager.unsubscribeFromRefresh(token: t) }
        eventToken = nil
        refreshToken = nil
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Private

    private func handleEvent(_ event: SSEEvent) {
        lastSSEEventAt = Date()
        switch event {
        case .sessionCreated(let session):
            // Insert at the top (most recent)
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
            }

        case .sessionUpdated(let session):
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.insert(session, at: 0)
            }

        case .sessionDeleted(let session):
            sessions.removeAll { $0.id == session.id }
            statusMap.removeValue(forKey: session.id)

        case .sessionStatus(let payload):
            statusMap[payload.sessionID] = payload.status

        case .projectUpdated(let project):
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
            } else {
                projects.append(project)
            }

        case .sessionIdle(let sessionID):
            statusMap[sessionID] = .idle

        case .sessionDiff(let payload):
            // Only act when the event carries data. The server publishes this event
            // with a hardcoded empty diff and simultaneously resets `Session.summary`
            // to {0, 0, 0}, so re-fetching on an empty payload never yields a summary
            // and just costs a request per event.
            if !payload.diff.isEmpty,
               let index = sessions.firstIndex(where: { $0.id == payload.sessionID }) {
                let sessionDirectory = sessions[index].directory
                Task { [weak self] in
                    guard let self, let client = self.connectionManager.activeAPIClient else { return }
                    if let updated = try? await SessionAPI(client: client, directory: sessionDirectory)
                        .get(id: payload.sessionID) {
                        if let idx = self.sessions.firstIndex(where: { $0.id == payload.sessionID }) {
                            self.sessions[idx] = updated
                        }
                    }
                }
            }

        default:
            break
        }
    }

    private func startStatusPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let shouldPoll = shouldPollStatuses
                let interval: TimeInterval = shouldPoll ? 4 : 15

                if shouldPoll {
                    await self.loadStatuses()
                    if Date().timeIntervalSince(self.lastSSEEventAt ?? .distantPast) > 8 {
                        await self.loadSessions()
                    }
                }

                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private var shouldPollStatuses: Bool {
        if statusMap.isEmpty { return true }
        return statusMap.values.contains { status in
            switch status {
            case .busy, .retry:
                return true
            case .idle:
                return false
            }
        }
    }
}
