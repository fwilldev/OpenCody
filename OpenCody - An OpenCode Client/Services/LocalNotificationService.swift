//
//  LocalNotificationService.swift
//  OpenCody - An OpenCode Client
//

import UserNotifications
import Foundation

/// Thin wrapper around UNUserNotificationCenter for permission-related local notifications.
/// All methods are best-effort — failures are silently logged, never surfaced to the user.
@MainActor
final class LocalNotificationService {

    static let shared = LocalNotificationService()
    private init() {}

    // MARK: - Authorization

    /// Request notification authorization on first launch.
    /// Should be called once from the app entry point after the user has connected a server.
    func requestAuthorization() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    print("[LocalNotificationService] Notification authorization granted.")
                } else {
                    print("[LocalNotificationService] Notification authorization denied.")
                }
            } catch {
                print("[LocalNotificationService] Authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Permission Notifications

    /// Fire a local notification alerting the user that a tool is waiting for permission.
    /// Best-effort only — if authorization is not granted the notification is silently dropped.
    func schedulePermissionNotification(_ request: Permission) {
        let content = UNMutableNotificationContent()
        content.title = "Permission Required"
        content.body = "Tool \"\(request.id)\" is waiting for your approval."
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"
        // Store the permission ID for potential deep-link handling
        content.userInfo = ["permissionID": request.id]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: "permission-\(request.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(notificationRequest) { error in
            if let error {
                print("[LocalNotificationService] Schedule error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Badge

    /// Clear all pending/delivered notifications and reset the app badge.
    func clearAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        Task { @MainActor in
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        }
    }
}
