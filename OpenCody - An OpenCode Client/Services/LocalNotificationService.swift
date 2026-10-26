//
//  LocalNotificationService.swift
//  OpenCody - An OpenCode Client
//

import UserNotifications
import Foundation

/// Thin wrapper around UNUserNotificationCenter for local notifications.
/// All methods are best-effort — failures are silently logged, never surfaced to the user.
@MainActor
final class LocalNotificationService {

    static let shared = LocalNotificationService()
    private init() {}

    // MARK: - Authorization

    /// Set once the authorization request has been issued in this process, so repeated
    /// foreground transitions don't ask (and log) again — the system prompt only ever
    /// appears once per install anyway.
    private var hasRequestedAuthorization = false

    /// Request notification authorization. Safe to call on every foreground transition;
    /// only the first call per app launch reaches the system.
    func requestAuthorization() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        Task {
            do {
                _ = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("[LocalNotificationService] Authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Posting

    /// Post the alerts whose kind the user left switched on and no push already showed.
    func post(_ alerts: [SessionAlert], server: UUID, settings: NotificationSettings = .shared) async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            .compactMap { $0.request.content.userInfo["dedupe"] as? String }
        let enabled = AlertKey.fresh(alerts.filter { settings.isEnabled($0.kind) }, delivered: delivered)
        for request in NotificationContent.requests(for: enabled, server: server) {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("[LocalNotificationService] Schedule error: \(error.localizedDescription)")
            }
        }
    }
}
