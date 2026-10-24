import SwiftUI

/// Navigation state shared by the compact (tab bar) and regular (sidebar) layouts.
///
/// Both layouts read the same `dashboardPath`, so a size class change (Split View,
/// Stage Manager, folding iPhone Duo) keeps the open project and chat.
@Observable
final class AppRouter {
    enum TabItem: Hashable {
        case dashboard
        case settings
    }

    enum Route: Hashable {
        /// A project's session list, keyed by its directory.
        case project(String)
        case chat(Session)
    }

    var selectedTab: TabItem = .dashboard
    var dashboardPath: [Route] = []
    var settingsPath = NavigationPath()

    // Sheets both layouts offer. Presented above the layout switch, so a resize keeps them open.
    var newSession: NewSessionRequest?
    var showAddServer = false
    var showTipJar = false

    struct NewSessionRequest: Identifiable {
        let id = UUID()
        /// Folder to preselect, when started from a project.
        var directory: String?
    }

    /// The project shown in the sidebar layout's detail column.
    var selectedProject: String? {
        guard case .project(let directory) = dashboardPath.first else { return nil }
        return directory
    }

    /// The session whose chat is on screen, so its notifications can be muted.
    var selectedSession: String? {
        guard case .chat(let session) = dashboardPath.last else { return nil }
        return session.id
    }

    func selectProject(_ directory: String?) {
        selectedTab = .dashboard
        guard directory != selectedProject || directory == nil else { return }
        dashboardPath = directory.map { [.project($0)] } ?? []
    }

    func navigateToSettings() {
        selectedTab = .settings
    }

    /// Opens a chat on top of its project, so both layouts can show it.
    func openChat(_ session: Session) {
        selectedTab = .dashboard
        dashboardPath = [.project(session.directory), .chat(session)]
    }
}
