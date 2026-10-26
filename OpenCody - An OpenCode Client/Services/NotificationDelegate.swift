import Foundation
import UserNotifications

/// Shows notifications while the app is open and opens their session when tapped.
/// Installed at launch, so the tap that launched the app is not lost.
@Observable
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// The tapped notification's session, until `RootView` opens it.
    var pendingLink: DeepLink?

    /// The session on screen; its own notifications stay quiet.
    @ObservationIgnored var viewingSessionID: () -> String? = { nil }

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // No actions yet; push will add them to these categories.
        center.setNotificationCategories(Set(SessionAlert.Kind.allCases.map {
            UNNotificationCategory(identifier: $0.rawValue, actions: [], intentIdentifiers: [])
        }))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let sessionID = notification.request.content.userInfo["sessionID"] as? String
        let viewing = await MainActor.run { viewingSessionID() }
        return sessionID != nil && sessionID == viewing ? [] : [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = DeepLink(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { pendingLink = link }
    }
}
