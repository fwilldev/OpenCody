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

    // MARK: - Category Identifiers

    enum Category {
        static let permissionRequest = "PERMISSION_REQUEST"
        static let turnComplete = "TURN_COMPLETE"
        static let sessionError = "SESSION_ERROR"
        static let questionAsked = "QUESTION_ASKED"
    }

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
        content.categoryIdentifier = Category.permissionRequest
        // Store the permission ID for potential deep-link handling
        content.userInfo = [
            "permissionID": request.id,
            "sessionID": request.sessionID,
        ]

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

    // MARK: - Turn Complete Notifications

    /// Fire a local notification when a session finishes generating (session.idle).
    func scheduleSessionIdleNotification(sessionID: String, sessionTitle: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Turn Complete"
        content.body = sessionTitle.map { "Session \"\($0)\" has finished." }
            ?? "A session has finished generating."
        content.sound = .default
        content.categoryIdentifier = Category.turnComplete
        content.userInfo = ["sessionID": sessionID]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: "idle-\(sessionID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(notificationRequest) { error in
            if let error {
                print("[LocalNotificationService] Schedule error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Error Notifications

    /// Fire a local notification when a session encounters an error.
    func scheduleSessionErrorNotification(sessionID: String, errorMessage: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Session Error"
        content.body = errorMessage ?? "A session encountered an error."
        content.sound = .default
        content.categoryIdentifier = Category.sessionError
        content.userInfo = ["sessionID": sessionID]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: "error-\(sessionID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(notificationRequest) { error in
            if let error {
                print("[LocalNotificationService] Schedule error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Question Notifications

    /// Fire a local notification when the agent asks a question.
    func scheduleQuestionNotification(sessionID: String, questionHeader: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Question From Agent"
        content.body = questionHeader ?? "The agent has a question for you."
        content.sound = .default
        content.categoryIdentifier = Category.questionAsked
        content.userInfo = ["sessionID": sessionID]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: "question-\(sessionID)-\(Date().timeIntervalSince1970)",
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
