//
//  SessionNotificationManager.swift
//  OpenCody - An OpenCode Client
//

import Foundation
import UIKit

// MARK: - SessionNotificationManager

/// Notifies about OpenCode 2.x sessions: live from the active server's event stream
/// (every project), and caught up from server state when the app becomes active.
/// 1.x servers get no notifications.
///
/// Runs on `MainActor` (project default) — safe for SwiftUI observation.
@Observable
final class SessionNotificationManager {

    @ObservationIgnored private let connectionManager: ConnectionManager
    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private let ledger = NotificationLedger()
    @ObservationIgnored private var eventToken: UUID?

    init(connectionManager: ConnectionManager, router: AppRouter) {
        self.connectionManager = connectionManager
        self.router = router
    }

    // MARK: - Lifecycle

    func startObserving() {
        guard eventToken == nil else { return }
        eventToken = connectionManager.subscribeToEvents { [weak self] event in
            guard case .sessionAlert(let alert) = event else { return }
            Task { await self?.handle(alert) }
        }
    }

    func stopObserving() {
        if let token = eventToken {
            connectionManager.unsubscribeFromEvents(token: token)
            eventToken = nil
        }
    }

    /// Asks for permission once there is a 2.x server, then posts what was missed.
    func becameActive() async {
        guard ServerStore.shared.load().contains(where: { $0.apiVersion == .v2 }) else { return }
        LocalNotificationService.shared.requestAuthorization()
        await BackgroundRefreshService.shared.catchUp(viewing: router.selectedSession)
        if let open = router.selectedSession { await markViewed(open) }
    }

    /// Tells the server the user saw the session's last run, as the OpenCode apps do,
    /// so it no longer counts as unread there or in a later catch-up.
    func markViewed(_ sessionID: String) async {
        guard let client = v2Client,
              let session = await Self.session(sessionID, client: client),
              session.isUnread, let idle = session.idle, let key = session.idleKey
        else { return }
        ledger.insert(key)
        try? await client.requestVoid(.v2("/api/session/\(sessionID)/view", method: .POST, json: ["idle": Int64(idle)]))
    }

    // MARK: - Live Alerts

    private var v2Client: APIClient? {
        guard let client = connectionManager.activeAPIClient, client.apiVersion == .v2 else { return nil }
        return client
    }

    private func handle(_ alert: SessionAlert) async {
        guard let server = connectionManager.activeServerID, let client = v2Client,
              // Sessions are read for the parent, title and idle time; a miss is left to catch-up.
              let session = await Self.session(alert.sessionID, client: client),
              let resolved = alert.resolved(with: session)
        else { return }

        if UIApplication.shared.applicationState == .active, resolved.sessionID == router.selectedSession {
            if resolved.kind == .finished || resolved.kind == .failed { await markViewed(resolved.sessionID) }
            ledger.insert(resolved.key)
            return
        }
        guard ledger.insert(resolved.key) else { return }
        await LocalNotificationService.shared.post([resolved], server: server)
    }

    private static func session(_ id: String, client: APIClient) async -> V2SessionState? {
        guard let data = try? await client.v2Data(.get("/api/session/\(id)")) as? [String: Any] else { return nil }
        return V2SessionState(json: data)
    }
}
