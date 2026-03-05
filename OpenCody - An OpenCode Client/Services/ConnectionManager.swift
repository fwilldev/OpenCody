//
//  ConnectionManager.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import Foundation
import SwiftUI

// MARK: - ConnectionManager

/// Manages live connections to one or more OpenCode servers.
///
/// Holds a dictionary mapping server IDs to their active connections (APIClient + EventService).
/// Provides a single `activeServerID` to designate which server's events are routed to the UI.
///
/// Runs on `MainActor` (project default) — safe for SwiftUI observation.
@Observable
final class ConnectionManager {

    // MARK: - Nested Types

    /// A live connection to a single OpenCode server.
    struct ActiveConnection {
        let server: ServerConnection
        let apiClient: APIClient
        let eventService: EventService
    }

    // MARK: - Observable State

    /// The currently selected server whose events are routed to the UI.
    private(set) var activeServerID: UUID?

    // MARK: - Ignored State (no SwiftUI re-renders)

    /// All live connections keyed by server ID.
    @ObservationIgnored
    private var connections: [UUID: ActiveConnection] = [:]

    /// Directory filter for SSE events (scoped to a project worktree).
    @ObservationIgnored
    private var activeEventDirectory: String? = nil

    /// Multi-subscriber event bus — keyed by subscription token.
    @ObservationIgnored
    private var eventSubscribers: [UUID: (SSEEvent) -> Void] = [:]

    /// Multi-subscriber refresh bus — keyed by subscription token.
    @ObservationIgnored
    private var refreshSubscribers: [UUID: () -> Void] = [:]

    // MARK: - Legacy Shim (single-callback compatibility)
    //
    // These expose the old `onEvent`/`onForegroundRefresh` interface so that any
    // code that hasn't yet migrated to the token-based API still compiles.
    // They use a stable private UUID key so they don't collide with token-based subscribers.

    @ObservationIgnored private let legacyEventKey = UUID()
    @ObservationIgnored private let legacyRefreshKey = UUID()

    /// Legacy single-callback shim. Prefer `subscribeToEvents(_:)` for new code.
    @ObservationIgnored
    var onEvent: ((SSEEvent) -> Void)? {
        get { eventSubscribers[legacyEventKey] }
        set {
            if let newValue {
                eventSubscribers[legacyEventKey] = newValue
            } else {
                eventSubscribers.removeValue(forKey: legacyEventKey)
            }
        }
    }

    /// Legacy single-callback shim. Prefer `subscribeToRefresh(_:)` for new code.
    @ObservationIgnored
    var onForegroundRefresh: (() -> Void)? {
        get { refreshSubscribers[legacyRefreshKey] }
        set {
            if let newValue {
                refreshSubscribers[legacyRefreshKey] = newValue
            } else {
                refreshSubscribers.removeValue(forKey: legacyRefreshKey)
            }
        }
    }

    // MARK: - Computed Properties

    /// The APIClient for the currently active server, if any.
    var activeAPIClient: APIClient? {
        guard let id = activeServerID else { return nil }
        return connections[id]?.apiClient
    }

    /// The EventService for the currently active server, if any.
    var activeEventService: EventService? {
        guard let id = activeServerID else { return nil }
        return connections[id]?.eventService
    }

    // MARK: - Token-Based Pub/Sub API

    /// Subscribe to SSE events from the active server.
    ///
    /// Multiple subscribers can coexist — each receives every event.
    /// - Parameter handler: Called on `MainActor` for each SSE event.
    /// - Returns: An opaque token. Pass to `unsubscribeFromEvents(token:)` to cancel.
    @discardableResult
    func subscribeToEvents(_ handler: @escaping (SSEEvent) -> Void) -> UUID {
        let token = UUID()
        eventSubscribers[token] = handler
        return token
    }

    /// Cancel an event subscription.
    /// - Parameter token: The token returned by `subscribeToEvents(_:)`.
    func unsubscribeFromEvents(token: UUID) {
        eventSubscribers.removeValue(forKey: token)
    }

    /// Subscribe to foreground-refresh notifications.
    ///
    /// Fired when the app transitions from background to active, signalling that
    /// ViewModels should refetch REST data.
    /// - Parameter handler: Called on `MainActor`.
    /// - Returns: An opaque token. Pass to `unsubscribeFromRefresh(token:)` to cancel.
    @discardableResult
    func subscribeToRefresh(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        refreshSubscribers[token] = handler
        return token
    }

    /// Cancel a refresh subscription.
    /// - Parameter token: The token returned by `subscribeToRefresh(_:)`.
    func unsubscribeFromRefresh(token: UUID) {
        refreshSubscribers.removeValue(forKey: token)
    }

    // MARK: - Connection Lifecycle

    /// Connect to an OpenCode server.
    ///
    /// Builds an `APIClient`, runs a health check, starts SSE event listening,
    /// and stores the connection. Sets this server as active if none is set.
    ///
    /// - Parameters:
    ///   - server: The server configuration to connect to.
    ///   - password: The password retrieved from Keychain.
    /// - Throws: `OpenCodeError.connectionFailed` if the health check fails.
    func connect(server: ServerConnection, password: String) async throws {
        // 1. Build APIClient
        let apiClient = APIClient(
            baseURL: server.baseURL,
            username: server.username,
            password: password
        )

        // 2. Health check
        let healthy: Bool
        do {
            healthy = try await apiClient.healthCheck()
        } catch {
            throw OpenCodeError.connectionFailed("Server health check failed")
        }

        guard healthy else {
            throw OpenCodeError.connectionFailed("Server health check failed")
        }

        // 3. Create EventService and wire up event routing
        let eventService = EventService()
        let serverID = server.id
        eventService.onEvent = { [weak self] (event: SSEEvent) in
            self?.routeEvent(event, serverID: serverID)
        }

        // 4. Start SSE listening
        eventService.startListening(apiClient: apiClient, directoryFilter: activeEventDirectory)

        // 5. Store connection
        connections[serverID] = ActiveConnection(
            server: server,
            apiClient: apiClient,
            eventService: eventService
        )

        // 6. Set as active if none set
        if activeServerID == nil {
            activeServerID = serverID
        }
    }

    /// Disconnect from a server.
    ///
    /// Stops SSE listening and removes the connection.
    /// If the disconnected server was active, clears `activeServerID`.
    ///
    /// - Parameter serverID: The UUID of the server to disconnect.
    func disconnect(serverID: UUID) {
        guard let connection = connections[serverID] else { return }
        connection.eventService.stopListening()
        connections.removeValue(forKey: serverID)

        if activeServerID == serverID {
            activeServerID = nil
        }
    }

    /// Switch the active server to another already-connected server.
    ///
    /// - Parameter id: The UUID of the server to activate. Must already be connected.
    func setActiveServer(_ id: UUID) {
        guard connections[id] != nil else { return }
        activeServerID = id
    }

    /// Connect to a server (if not already connected) and set it as the active server.
    ///
    /// Retrieves the stored password from Keychain and calls `connect(server:password:)`.
    /// On success, sets this server as the active server.
    /// On failure, stores an offline connection so the UI can show the offline state
    /// with a reconnect button.
    ///
    /// - Parameter server: The server to connect and activate.
    func connectAndActivate(server: ServerConnection) {
        // Already connected — just switch
        if connections[server.id] != nil {
            activeServerID = server.id
            return
        }
        let password = (try? KeychainService.retrieve(for: server.keychainIdentifier)) ?? ""
        Task {
            do {
                try await connect(server: server, password: password)
            } catch {
                // Server unreachable — store an offline connection so the UI
                // can show the offline state with a reconnect button
                let apiClient = APIClient(
                    baseURL: server.baseURL,
                    username: server.username,
                    password: password
                )
                let eventService = EventService()
                let serverID = server.id
                eventService.onEvent = { [weak self] (event: SSEEvent) in
                    self?.routeEvent(event, serverID: serverID)
                }
                eventService.connectionState = .offline
                connections[serverID] = ActiveConnection(
                    server: server,
                    apiClient: apiClient,
                    eventService: eventService
                )
            }
            // connect() sets activeServerID only if nil — force set it here
            activeServerID = server.id
        }
    }

    /// Update the active directory filter used for SSE events.
    /// If changed, restarts SSE listening for the active server.
    func setActiveEventDirectory(_ directory: String?) {
        var normalized = directory?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = normalized, !value.isEmpty, !value.hasPrefix("/") {
            normalized = "/" + value
        }
        guard normalized != activeEventDirectory else { return }
        activeEventDirectory = normalized

        guard let id = activeServerID, let connection = connections[id] else { return }
        connection.eventService.startListening(apiClient: connection.apiClient, directoryFilter: activeEventDirectory)
    }

    /// Returns the current connection state for a server.
    ///
    /// - Parameter serverID: The UUID of the server to query.
    /// - Returns: The `ConnectionState`, or `.idle` if not connected.
    func connectionState(for serverID: UUID) -> ConnectionState {
        guard let connection = connections[serverID] else { return .idle }
        return connection.eventService.connectionState
    }

    /// Manually retry connecting to a server that went offline.
    ///
    /// Performs a health check first. If healthy, restarts SSE listening.
    /// If the health check fails, sets the connection state back to `.offline`.
    ///
    /// - Parameter serverID: The UUID of the server to retry.
    func retryConnection(for serverID: UUID) async {
        guard let connection = connections[serverID] else { return }

        connection.eventService.connectionState = .connecting

        let healthy: Bool
        do {
            healthy = try await connection.apiClient.healthCheck()
        } catch {
            connection.eventService.connectionState = .offline
            return
        }

        guard healthy else {
            connection.eventService.connectionState = .offline
            return
        }

        connection.eventService.startListening(
            apiClient: connection.apiClient,
            directoryFilter: activeEventDirectory
        )
    }

    // MARK: - Scene Phase

    /// Handle app lifecycle changes.
    ///
    /// On `.active`: triggers a foreground refresh so ViewModels can reload REST data.
    /// On `.background`: no action needed (SSE auto-reconnects).
    ///
    /// - Parameter phase: The new `ScenePhase`.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            refetchOnForeground()
        case .background, .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Private

    /// Routes an SSE event to all event subscribers, but only if it comes from the active server.
    private func routeEvent(_ event: SSEEvent, serverID: UUID) {
        guard serverID == activeServerID else { return }
        for handler in eventSubscribers.values {
            handler(event)
        }
    }

    /// Triggers all foreground-refresh subscribers so ViewModels can reload REST data.
    private func refetchOnForeground() {
        for handler in refreshSubscribers.values {
            handler()
        }
    }
}
