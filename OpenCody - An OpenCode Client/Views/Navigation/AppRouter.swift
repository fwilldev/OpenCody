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

    /// Every pushed screen, so all stacks share one destination type (`RouteDestination`).
    enum Route: Hashable {
        /// A project's session list, keyed by its directory.
        case project(String)
        case chat(Session)
        case settings(SettingsRoute)
    }

    /// Settings screens, pushed by value so `settingsPath` (and a resize) keeps them.
    enum SettingsRoute: Hashable {
        case servers, providers, mcp, tipJar, licenses
        case push(UUID)
    }

    var selectedTab: TabItem = .dashboard
    var dashboardPath: [Route] = []
    var settingsPath: [Route] = []

    /// The sidebar layout's single detail stack: the Settings screens, or what's above the
    /// selected project. One stack with one path type, so switching between them never swaps
    /// stacks inside the split view's detail column.
    var detailPath: [Route] {
        get { selectedTab == .settings ? settingsPath : Array(dashboardPath.dropFirst()) }
        set {
            if selectedTab == .settings {
                settingsPath = newValue
            } else {
                dashboardPath = Array(dashboardPath.prefix(1)) + newValue
            }
        }
    }

    // Sheets both layouts offer. Presented above the layout switch, so a resize keeps them open.
    var newSession: NewSessionRequest?
    var showAddServer = false
    var showTipJar = false
    /// Rename alerts, held here so the view the other layout creates shows them again.
    var renamingProject: ProjectGroup?
    var renamingSession: Session?
    /// The server list's edit and pairing sheets, for the same reason.
    var selectedServer: ServerConnection?
    var pairingServer: ServerConnection?
    var pushServer: ServerConnection?

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

    /// The sidebar's selected project row; none while Settings is shown.
    var sidebarProject: String? {
        get { selectedTab == .settings ? nil : selectedProject }
        set { selectProject(newValue) }
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
