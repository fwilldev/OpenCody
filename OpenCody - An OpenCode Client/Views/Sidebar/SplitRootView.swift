//
//  SplitRootView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Regular-width layout (iPad, iPhone Duo's inner display): sidebar plus detail.
///
/// All navigation lives in `AppRouter`, shared with the compact layout, so switching
/// between the two on a resize keeps the selected project and the open chat.
struct SplitRootView: View {
    let viewModel: DashboardViewModel
    let connectionManager: ConnectionManager

    @Environment(AppRouter.self) private var router
    @EnvironmentObject private var serverStore: ServerStoreModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Whether the active server's connection is in the offline state.
    private var isActiveServerOffline: Bool {
        guard let id = connectionManager.activeServerID else { return false }
        return connectionManager.connectionState(for: id) == .offline
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                connectionManager: connectionManager,
                viewModel: viewModel,
                selectedProjectKey: projectSelection,
                openSettings: router.navigateToSettings
            )
            .navigationTitle("OpenCody")
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.Colors.cyberBlue)
        .task(id: connectionManager.activeServerID) {
            await waitForActiveClient()
            viewModel.loadClosedProjects()
            await viewModel.loadSessions()
            await viewModel.loadStatuses()
            await viewModel.loadProjects()
        }
        .onChange(of: connectionManager.activeAPIClient != nil) { _, hasClient in
            guard hasClient else { return }
            Task {
                await viewModel.loadSessions()
                await viewModel.loadStatuses()
            }
        }
        .onChange(of: isActiveServerOffline) { wasOffline, isOffline in
            // When transitioning from offline → online, reload data
            if wasOffline && !isOffline {
                Task {
                    await viewModel.loadSessions()
                    await viewModel.loadStatuses()
                }
            }
        }
        .onAppear { viewModel.startObservingEvents() }
        .onDisappear { viewModel.stopObservingEvents() }
    }

    // MARK: - Navigation Bindings

    private var projectSelection: Binding<String?> {
        Binding(
            get: { router.selectedTab == .settings ? nil : router.selectedProject },
            set: { router.selectProject($0) }
        )
    }

    /// The detail column's stack: everything above the selected project.
    private var detailPath: Binding<[AppRouter.Route]> {
        Binding(
            get: { Array(router.dashboardPath.dropFirst()) },
            set: { router.dashboardPath = Array(router.dashboardPath.prefix(1)) + $0 }
        )
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        @Bindable var router = router
        if router.selectedTab == .settings {
            NavigationStack(path: $router.settingsPath) {
                SettingsView(connectionManager: connectionManager)
            }
        } else if let directory = router.selectedProject {
            NavigationStack(path: detailPath) {
                ProjectSessionsView(
                    projectPath: directory,
                    viewModel: viewModel,
                    connectionManager: connectionManager
                )
                .navigationDestination(for: AppRouter.Route.self) { route in
                    switch route {
                    case .project(let directory):
                        ProjectSessionsView(projectPath: directory, viewModel: viewModel, connectionManager: connectionManager)
                    case .chat(let session):
                        ChatWithUtilitiesView(session: session, connectionManager: connectionManager)
                    }
                }
            }
        } else {
            emptyContent
        }
    }

    // MARK: - Empty State

    private var emptyContent: some View {
        Group {
            if isActiveServerOffline {
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: "Server Offline",
                    message: "The server could not be reached after multiple attempts. Tap to try again.",
                    action: {
                        guard let id = connectionManager.activeServerID else { return }
                        Task {
                            await connectionManager.retryConnection(for: id)
                        }
                    },
                    actionLabel: "Reconnect"
                )
            } else if connectionManager.activeAPIClient == nil && serverStore.servers.isEmpty {
                EmptyStateView(
                    systemImage: "server.rack",
                    title: "No Server Connected",
                    message: "Add a server to get started.",
                    action: { router.showAddServer = true },
                    actionLabel: "Add Server"
                )
            } else if connectionManager.activeAPIClient == nil {
                ContentUnavailableView {
                    ProgressView("Connecting…")
                } actions: {
                    Button("Manage Servers", action: router.navigateToSettings)
                }
            } else {
                EmptyStateView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No Project Selected",
                    message: "Pick a project in the sidebar, or start a new session.",
                    action: { router.newSession = .init() },
                    actionLabel: "New Session"
                )
            }
        }
        .background(Theme.Colors.deepBlack)
    }

    // MARK: - Helpers

    private func waitForActiveClient() async {
        if connectionManager.activeAPIClient != nil { return }
        for _ in 0..<20 {
            if connectionManager.activeAPIClient != nil { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }
}
