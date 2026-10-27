import SwiftUI

/// The screen for a pushed `AppRouter.Route`, the same in every navigation stack.
struct RouteDestination: View {
    let route: AppRouter.Route
    let viewModel: DashboardViewModel
    let connectionManager: ConnectionManager

    var body: some View {
        switch route {
        case .project(let directory):
            ProjectSessionsView(projectPath: directory, viewModel: viewModel, connectionManager: connectionManager)
        case .chat(let session):
            ChatView(session: session, connectionManager: connectionManager)
        case .settings(.servers):
            ServerListView(connectionManager: connectionManager)
        case .settings(.providers):
            if let apiClient = connectionManager.activeAPIClient {
                ProvidersView(apiClient: apiClient)
            } else {
                notConnected("Providers")
            }
        case .settings(.mcp):
            if let apiClient = connectionManager.activeAPIClient {
                MCPView(apiClient: apiClient)
            } else {
                notConnected("MCP Servers")
            }
        case .settings(.tipJar):
            TipJarView()
        case .settings(.licenses):
            LicensesView()
        case .settings(.privacy):
            PrivacyPolicyView()
        }
    }

    private func notConnected(_ name: String) -> some View {
        EmptyStateView(
            systemImage: "wifi.slash",
            title: "Not Connected",
            message: "Connect to a server in the Servers section to access \(name)."
        )
        .background(Theme.Colors.deepBlack)
        .navigationTitle(name)
    }
}

extension View {
    /// Registers `RouteDestination` for a navigation stack; once per stack.
    func routeDestinations(viewModel: DashboardViewModel, connectionManager: ConnectionManager) -> some View {
        navigationDestination(for: AppRouter.Route.self) { route in
            RouteDestination(route: route, viewModel: viewModel, connectionManager: connectionManager)
        }
    }
}
