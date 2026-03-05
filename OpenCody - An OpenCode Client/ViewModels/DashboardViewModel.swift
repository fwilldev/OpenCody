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

    // MARK: - Dependencies

    @ObservationIgnored private let connectionManager: ConnectionManager
    @ObservationIgnored private let closedProjectsStore = ClosedProjectsStore.shared

    // MARK: - Init

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
    }

    // MARK: - Closed Projects

    /// Load closed-projects state for the active server.
    func loadClosedProjects() {
        guard let serverID = connectionManager.activeServerID else { return }
        closedProjectsStore.load(for: serverID)
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

        let api = SessionAPI(client: client)

        let normalizedPath = normalizePath(path)

        // Auto-reopen if the project was previously closed
        if let serverID = connectionManager.activeServerID {
            closedProjectsStore.reopenIfClosed(directory: normalizedPath, serverID: serverID)
        }

        let session = try await api.create(directory: normalizedPath)

        // Insert the new session immediately instead of relying on loadSessions(),
        // which can be cancelled by SwiftUI task management and cause spurious errors.
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.insert(session, at: 0)
        }

        return session
    }

    /// Delete a session by ID.
    func deleteSession(id: String) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let api = SessionAPI(client: client)
        try await api.delete(id: id)
        sessions.removeAll { $0.id == id }
        statusMap.removeValue(forKey: id)
    }

    /// Archive a session.
    func archiveSession(id: String) async throws {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let api = SessionAPI(client: client)
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

        let api = SessionAPI(client: client)
        let updated = try await api.update(id: id, setArchived: false)
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = updated
        }
    }

    // MARK: - SSE Event Observation

    @ObservationIgnored private var eventToken: UUID?
    @ObservationIgnored private var refreshToken: UUID?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastSSEEventAt: Date?

    /// Subscribe to SSE events for live session updates.
    func startObservingEvents() {
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

        case .sessionIdle(let sessionID):
            statusMap[sessionID] = .idle

        case .sessionDiff(let payload):
            // session.diff arrives after session.updated, which should carry the summary.
            // As a safety net, if the session in our list still has no summary, re-fetch it.
            if let index = sessions.firstIndex(where: { $0.id == payload.sessionID }),
               sessions[index].summary == nil || sessions[index].summary?.files == 0 {
                Task { [weak self] in
                    guard let self, let client = self.connectionManager.activeAPIClient else { return }
                    if let updated = try? await SessionAPI(client: client).get(id: payload.sessionID) {
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

    private func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
