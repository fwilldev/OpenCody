import SwiftUI

@Observable
final class AppRouter {
    enum TabItem: Hashable {
        case dashboard
        case settings
    }

    var selectedTab: TabItem = .dashboard
    var dashboardPath = NavigationPath()
    var settingsPath = NavigationPath()
    var selectedSession: String? = nil

    func navigateToSession(_ sessionId: String) {
        selectedSession = sessionId
    }

    func navigateToSettings() {
        selectedTab = .settings
    }

    func popToRoot() {
        dashboardPath = NavigationPath()
        settingsPath = NavigationPath()
    }
}
