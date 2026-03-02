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

    // MARK: - Dependencies

    @ObservationIgnored private let connectionManager: ConnectionManager

    // MARK: - Init

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
    }

    // MARK: - Session Loading

    /// Fetch all sessions from the active server.
    func loadSessions() async {
        guard let client = connectionManager.activeAPIClient else {
            // No server connected — empty state handles this, no error needed
            sessions = []
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
    func createSession(
        path: String,
        agentName: String?,
        modelID: String?,
        providerID: String?
    ) async throws -> Session {
        guard let client = connectionManager.activeAPIClient else {
            throw OpenCodeError.connectionFailed("No active server connection")
        }

        let api = SessionAPI(client: client)

        let normalizedPath = normalizePath(path)
        let session = try await api.create(directory: normalizedPath)

        // Initialize the session with agent/model settings if provided
        if agentName != nil || modelID != nil || providerID != nil {
            _ = try? await api.initialize(
                id: session.id,
                agent: agentName,
                modelID: modelID,
                providerID: providerID
            )
        }

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
        let standardized = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return standardized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
