//
//  SessionNotificationManager.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - SessionNotificationManager

/// Subscribes to SSE events and routes user-facing notifications.
///
/// Notification events:
/// - `session.idle` → Turn complete (only if session was busy)
/// - `session.error` → Error notification
/// - `permission.updated` → Permission required
/// - `question.asked` → Agent question
///
/// Suppression rules:
/// - Skip if session is the currently active (open) session
/// - Skip if session is a child of the currently active session
/// - 5-second cooldown per session for permission/question events
///
/// Runs on `MainActor` (project default) — safe for SwiftUI observation.
@Observable
final class SessionNotificationManager {

    // MARK: - Dependencies

    @ObservationIgnored private let connectionManager: ConnectionManager
    @ObservationIgnored private let router: AppRouter
    @ObservationIgnored private let settings: NotificationSettings
    @ObservationIgnored private let store: NotificationStore
    @ObservationIgnored private let localNotifications: LocalNotificationService

    // MARK: - Internal State

    /// Subscription token for SSE events.
    @ObservationIgnored private var eventToken: UUID?

    /// Sessions that are currently busy (generating). Cleared on idle.
    /// Used to only fire turn-complete for sessions that were actually generating.
    @ObservationIgnored private var busySessions: Set<String> = []

    /// Lightweight session metadata cache for parent-child lookups and titles.
    @ObservationIgnored private var sessionCache: [String: CachedSession] = [:]

    /// Last notification timestamp per session for permission/question cooldown.
    @ObservationIgnored private var cooldowns: [String: Date] = [:]

    /// Cooldown duration for permission/question notifications per session.
    private let cooldownInterval: TimeInterval = 5.0

    // MARK: - Cached Session

    /// Minimal session info needed for notification logic.
    private struct CachedSession {
        let title: String
        let parentID: String?
    }

    // MARK: - Init

    init(
        connectionManager: ConnectionManager,
        router: AppRouter,
        settings: NotificationSettings = .shared,
        store: NotificationStore,
        localNotifications: LocalNotificationService = .shared
    ) {
        self.connectionManager = connectionManager
        self.router = router
        self.settings = settings
        self.store = store
        self.localNotifications = localNotifications
    }

    // MARK: - Lifecycle

    /// Start observing SSE events. Call once from the root view.
    func startObserving() {
        guard eventToken == nil else { return }
        eventToken = connectionManager.subscribeToEvents { [weak self] event in
            self?.handleEvent(event)
        }
    }

    /// Stop observing SSE events. Call on teardown.
    func stopObserving() {
        if let token = eventToken {
            connectionManager.unsubscribeFromEvents(token: token)
            eventToken = nil
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: SSEEvent) {
        // Keep session cache updated from session lifecycle events
        switch event {
        case .sessionCreated(let session), .sessionUpdated(let session):
            sessionCache[session.id] = CachedSession(
                title: session.title,
                parentID: session.parentID
            )

        case .sessionDeleted(let session):
            sessionCache.removeValue(forKey: session.id)
            busySessions.remove(session.id)
            cooldowns.removeValue(forKey: session.id)

        case .sessionStatus(let payload):
            switch payload.status {
            case .busy, .retry:
                busySessions.insert(payload.sessionID)
            case .idle:
                // Don't remove here — sessionIdle handles the notification + cleanup
                break
            }

        default:
            break
        }

        // Route notification events
        switch event {
        case .sessionIdle(let sessionID):
            handleSessionIdle(sessionID: sessionID)

        case .sessionError(let payload):
            handleSessionError(payload)

        case .permissionUpdated(let permission):
            handlePermissionUpdated(permission)

        case .questionAsked(let request):
            handleQuestionAsked(request)

        default:
            break
        }
    }

    // MARK: - Session Idle (Turn Complete)

    private func handleSessionIdle(sessionID: String) {
        // Only notify if this session was actually generating
        guard busySessions.remove(sessionID) != nil else { return }
        guard settings.turnCompleteEnabled else { return }
        guard !isSuppressed(sessionID: sessionID) else { return }

        let title = sessionCache[sessionID]?.title
        let displayTitle = title.flatMap { $0.isEmpty ? nil : $0 }

        // OS notification
        localNotifications.scheduleSessionIdleNotification(
            sessionID: sessionID,
            sessionTitle: displayTitle
        )

        // In-app entry
        store.add(NotificationEntry(
            type: .turnComplete,
            sessionID: sessionID,
            title: "Turn Complete",
            body: displayTitle.map { "Session \"\($0)\" has finished." }
                ?? "A session has finished generating."
        ))
    }

    // MARK: - Session Error

    private func handleSessionError(_ payload: SessionErrorPayload) {
        guard let sessionID = payload.sessionID else { return }
        guard settings.errorsEnabled else { return }
        guard !isSuppressed(sessionID: sessionID) else { return }

        let errorMessage = payload.error.flatMap { Self.extractMessage(from: $0) }

        // OS notification
        localNotifications.scheduleSessionErrorNotification(
            sessionID: sessionID,
            errorMessage: errorMessage
        )

        // In-app entry
        store.add(NotificationEntry(
            type: .error,
            sessionID: sessionID,
            title: "Session Error",
            body: errorMessage ?? "A session encountered an error."
        ))
    }

    // MARK: - Permission Updated

    private func handlePermissionUpdated(_ permission: Permission) {
        let sessionID = permission.sessionID
        guard settings.permissionsEnabled else { return }
        guard !isSuppressed(sessionID: sessionID) else { return }
        guard !isCooldownActive(for: sessionID) else { return }

        // TODO: Skip if permission was auto-responded.
        // No auto-respond mechanism exists yet; add check here when implemented.

        recordCooldown(for: sessionID)

        // OS notification
        localNotifications.schedulePermissionNotification(permission)

        // In-app entry
        store.add(NotificationEntry(
            type: .permission,
            sessionID: sessionID,
            title: "Permission Required",
            body: "Tool \"\(permission.displayTitle)\" is waiting for approval."
        ))
    }

    // MARK: - Question Asked

    private func handleQuestionAsked(_ request: QuestionRequest) {
        let sessionID = request.sessionID
        guard settings.questionsEnabled else { return }
        guard !isSuppressed(sessionID: sessionID) else { return }
        guard !isCooldownActive(for: sessionID) else { return }

        recordCooldown(for: sessionID)

        let header = request.questions.first?.header

        // OS notification
        localNotifications.scheduleQuestionNotification(
            sessionID: sessionID,
            questionHeader: header
        )

        // In-app entry
        store.add(NotificationEntry(
            type: .question,
            sessionID: sessionID,
            title: "Question From Agent",
            body: header ?? "The agent has a question for you."
        ))
    }

    // MARK: - Suppression Logic

    /// Returns `true` if notifications for this session should be suppressed.
    ///
    /// Suppressed when:
    /// 1. The session is the currently active (open) session
    /// 2. The session is a child of the currently active session
    private func isSuppressed(sessionID: String) -> Bool {
        guard let activeID = router.selectedSession else {
            // No session is open — don't suppress
            return false
        }

        // Rule 1: Session is active
        if sessionID == activeID {
            return true
        }

        // Rule 2: Session is a child of the active session
        if let cached = sessionCache[sessionID], cached.parentID == activeID {
            return true
        }

        return false
    }

    // MARK: - Cooldown Logic

    /// Returns `true` if the 5-second cooldown is still active for this session.
    private func isCooldownActive(for sessionID: String) -> Bool {
        guard let lastFired = cooldowns[sessionID] else { return false }
        return Date().timeIntervalSince(lastFired) < cooldownInterval
    }

    /// Record a cooldown timestamp for a session.
    private func recordCooldown(for sessionID: String) {
        cooldowns[sessionID] = Date()
    }

    // MARK: - Helpers

    /// Extract a user-facing message string from a `MessageError` enum.
    private static func extractMessage(from error: MessageError) -> String {
        switch error {
        case .providerAuth(_, let message):
            return message
        case .unknown(let message):
            return message
        case .outputLength:
            return "Output length limit reached."
        case .aborted(let message):
            return message
        case .api(let data):
            return data.message
        }
    }
}
