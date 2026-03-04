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

    @State private var selectedProjectKey: String? = nil
    @State private var showCreateSheet: Bool = false
    @State private var showAddServer: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var detailPath = NavigationPath()
    @State private var showSettings: Bool = false

    /// Shared DashboardViewModel for sidebar + detail.
    @State private var dashboardViewModel: DashboardViewModel

    init(router: AppRouter, connectionManager: ConnectionManager) {
        self.router = router
        self.connectionManager = connectionManager
        self._dashboardViewModel = State(initialValue: DashboardViewModel(connectionManager: connectionManager))
    }

    // MARK: - Body

    var body: some View {
        let sidebar = iPadSidebarView(
            connectionManager: connectionManager,
            viewModel: dashboardViewModel,
            selectedProjectKey: $selectedProjectKey,
            showCreateSheet: $showCreateSheet,
            openServers: openServers,
            openSettings: {
                selectedProjectKey = nil
                showSettings = true
            }
        )

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
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
                viewModel: dashboardViewModel,
                connectionManager: connectionManager
            )
        }
        .sheet(isPresented: $showAddServer) {
            AddServerView(connectionManager: connectionManager)
                .environmentObject(serverStore)
        }
        .task(id: connectionManager.activeServerID) {
            dashboardViewModel.stopObservingEvents()
            await waitForActiveClient()
            await dashboardViewModel.loadSessions()
            await dashboardViewModel.loadStatuses()
            dashboardViewModel.startObservingEvents()
        }
        .onChange(of: connectionManager.activeAPIClient != nil) { _, hasClient in
            guard hasClient else { return }
            Task {
                await dashboardViewModel.loadSessions()
                await dashboardViewModel.loadStatuses()
            }
        }
        .onDisappear {
            dashboardViewModel.stopObservingEvents()
        }
        .onChange(of: selectedProjectKey) { _, _ in
            detailPath = NavigationPath()
            showSettings = false
        }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        if showSettings {
            return AnyView(
                NavigationStack {
                    SettingsView(connectionManager: connectionManager)
                        .environmentObject(serverStore)
                }
            )
        }

        if let projectKey = selectedProjectKey,
           let group = sessionsByProject.first(where: { $0.key == projectKey }) {
            return AnyView(
                NavigationStack(path: $detailPath) {
                    ProjectSessionsView(
                        projectName: group.key,
                        projectPath: group.sessions.first?.directory,
                        initialStatusMap: dashboardViewModel.statusMap,
                        viewModel: dashboardViewModel,
                        connectionManager: connectionManager
                    )
                }
            )
        }

        return AnyView(settingsOrEmptyContent)
    }

    private var sessionsByProject: [(key: String, sessions: [Session])] {
        let grouped = Dictionary(grouping: dashboardViewModel.sessions) { (session: Session) -> String in
            let components = session.directory
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/")
            return components.last.map(String.init) ?? session.directory
        }
        return grouped
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { (key: $0.key, sessions: $0.value.sorted { $0.time.updated > $1.time.updated }) }
    }

    // MARK: - Empty / Settings State

    private var settingsOrEmptyContent: some View {
        Group {
            if connectionManager.activeAPIClient == nil && serverStore.servers.isEmpty {
                EmptyStateView(
                    systemImage: "server.rack",
                    title: "No Server Connected",
                    message: "Add a server to get started.",
                    action: { showAddServer = true },
                    actionLabel: "Add Server"
                )
            } else if connectionManager.activeAPIClient == nil {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView("Connecting…")
                        .tint(Theme.Colors.cyberBlue)
                    Button("Manage Servers") {
                        openServers()
                    }
                    .font(Theme.Fonts.captionBold)
                    .foregroundStyle(Theme.Colors.cyberBlue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No Session Selected",
                    message: "Select a session from the sidebar or create a new one.",
                    action: { showCreateSheet = true },
                    actionLabel: "New Session"
                )
            }
        }
        .background(Theme.Colors.deepBlack)
    }

    // MARK: - Helpers

    private func openServers() {
        selectedProjectKey = nil
        showSettings = true
    }

    private func waitForActiveClient() async {
        if connectionManager.activeAPIClient != nil { return }
        for _ in 0..<20 {
            if connectionManager.activeAPIClient != nil { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }
}
