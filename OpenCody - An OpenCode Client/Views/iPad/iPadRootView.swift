//
//  iPadRootView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// iPad layout using NavigationSplitView with a real sidebar and detail pane.
struct iPadRootView: View {
    let router: AppRouter
    let connectionManager: ConnectionManager

    @EnvironmentObject private var serverStore: ServerStoreModel

    @State private var selectedSessionID: String? = nil
    @State private var showCreateSheet: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    /// Dedicated DashboardViewModel for looking up sessions by ID in the detail pane.
    @State private var detailViewModel: DashboardViewModel

    init(router: AppRouter, connectionManager: ConnectionManager) {
        self.router = router
        self.connectionManager = connectionManager
        self._detailViewModel = State(initialValue: DashboardViewModel(connectionManager: connectionManager))
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            iPadSidebarView(
                connectionManager: connectionManager,
                selectedSessionID: $selectedSessionID,
                showCreateSheet: $showCreateSheet
            )
            .environmentObject(serverStore)
            .navigationTitle("OpenCody")
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.Colors.cyberBlue)
        .sheet(isPresented: $showCreateSheet) {
            CreateSessionSheet(
                viewModel: detailViewModel,
                connectionManager: connectionManager
            )
        }
        .task {
            await detailViewModel.loadSessions()
        }
        .onChange(of: selectedSessionID) { _, newValue in
            router.selectedSession = newValue
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let sessionID = selectedSessionID,
           let session = detailViewModel.sessions.first(where: { $0.id == sessionID }) {
            NavigationStack {
                ChatView(session: session, connectionManager: connectionManager)
                    .id(sessionID)
                    .navigationDestination(for: iPadSettingsDestination.self) { destination in
                        settingsDestinationView(for: destination)
                    }
            }
        } else {
            NavigationStack {
                settingsOrEmptyContent
                    .navigationDestination(for: iPadSettingsDestination.self) { destination in
                        settingsDestinationView(for: destination)
                    }
            }
        }
    }

    // MARK: - Empty / Settings State

    private var settingsOrEmptyContent: some View {
        EmptyStateView(
            systemImage: "bubble.left.and.bubble.right",
            title: "No Session Selected",
            message: "Select a session from the sidebar or create a new one.",
            action: { showCreateSheet = true },
            actionLabel: "New Session"
        )
        .background(Theme.Colors.deepBlack)
    }

    // MARK: - Settings Destinations

    @ViewBuilder
    private func settingsDestinationView(for destination: iPadSettingsDestination) -> some View {
        switch destination {
        case .servers:
            ServerListView(connectionManager: connectionManager)
                .environmentObject(serverStore)
        case .providers:
            if let apiClient = connectionManager.activeAPIClient {
                ProvidersView(apiClient: apiClient)
            } else {
                noConnectionView(for: "Providers")
            }
        case .mcp:
            if let apiClient = connectionManager.activeAPIClient {
                MCPView(apiClient: apiClient)
            } else {
                noConnectionView(for: "MCP Servers")
            }
        case .serverConfig:
            if let apiClient = connectionManager.activeAPIClient {
                ServerConfigView(apiClient: apiClient)
            } else {
                noConnectionView(for: "Server Config")
            }
        }
    }

    private func noConnectionView(for name: String) -> some View {
        EmptyStateView(
            systemImage: "wifi.slash",
            title: "Not Connected",
            message: "Connect to a server in the Servers section to access \(name)."
        )
        .background(Theme.Colors.deepBlack)
        .navigationTitle(name)
    }
}
