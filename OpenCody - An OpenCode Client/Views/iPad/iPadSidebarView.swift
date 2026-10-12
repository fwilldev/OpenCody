//
//  iPadSidebarView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// iPad sidebar with server switcher, live session list, and settings links.
struct iPadSidebarView: View {
    let connectionManager: ConnectionManager
    let viewModel: DashboardViewModel
    @Binding var selectedProjectKey: String?
    @Binding var showCreateSheet: Bool
    let openServers: () -> Void
    let openSettings: () -> Void

    @EnvironmentObject private var serverStore: ServerStoreModel
    @State private var showTipJar: Bool = false
    @State private var renamingProject: ProjectGroup?

    /// Whether the active server's connection is in the offline state.
    private var isActiveServerOffline: Bool {
        guard let id = connectionManager.activeServerID else { return false }
        return connectionManager.connectionState(for: id) == .offline
    }

    // MARK: - Init

    init(
        connectionManager: ConnectionManager,
        viewModel: DashboardViewModel,
        selectedProjectKey: Binding<String?>,
        showCreateSheet: Binding<Bool>,
        openServers: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.connectionManager = connectionManager
        self.viewModel = viewModel
        self._selectedProjectKey = selectedProjectKey
        self._showCreateSheet = showCreateSheet
        self.openServers = openServers
        self.openSettings = openSettings
    }

    // MARK: - Body

    var body: some View {
        List(selection: $selectedProjectKey) {
            if let errorMessage = viewModel.error {
                Section {
                    ErrorBanner(
                        error: .network(errorMessage),
                        onDismiss: { viewModel.error = nil }
                    )
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // MARK: Server Switcher
            Section {
                serverSwitcherRow
            } header: {
                sectionHeader("Server")
            }

            // MARK: Projects
            Section {
                if isActiveServerOffline {
                    ContentUnavailableView {
                        Label("Server Offline", systemImage: "wifi.slash")
                    } description: {
                        Text("Could not reach the server.")
                    } actions: {
                        Button("Reconnect") {
                            guard let id = connectionManager.activeServerID else { return }
                            Task { await connectionManager.retryConnection(for: id) }
                        }
                    }
                } else if connectionManager.activeAPIClient == nil && !serverStore.servers.isEmpty {
                    ProgressView("Connecting…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                } else if connectionManager.activeAPIClient == nil {
                    ContentUnavailableView {
                        Label("No Server Connected", systemImage: "server.rack")
                    } description: {
                        Text("Add a server to get started.")
                    } actions: {
                        Button("Manage Servers", action: openServers)
                    }
                } else if viewModel.activeSessions.isEmpty && !viewModel.isLoading {
                    Text("No sessions")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                } else {
                    ForEach(viewModel.projectGroups) { project in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(Theme.Fonts.bodyBold)
                                    .foregroundStyle(Theme.Colors.cloud)
                                    .lineLimit(1)
                                if project.hasCustomName {
                                    Text(project.directory)
                                        .font(Theme.Fonts.codeCaption)
                                        .foregroundStyle(Theme.Colors.silver)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.Colors.cyberBlue)
                        }
                        .opacity(viewModel.isProjectClosed(directory: project.directory) ? 0.5 : 1.0)
                        .tag(project.directory)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if viewModel.isProjectClosed(directory: project.directory) {
                                Button("Open", systemImage: "eye") {
                                    withAnimation { viewModel.reopenProject(directory: project.directory) }
                                }
                                .tint(.blue)
                            } else {
                                Button("Close", systemImage: "eye.slash") {
                                    withAnimation { viewModel.closeProject(directory: project.directory) }
                                }
                                .tint(.orange)
                            }
                        }
                        .contextMenu {
                            ProjectContextMenu(group: project, viewModel: viewModel) {
                                renamingProject = project
                            }
                        }
                    }

                    // Show/hide closed projects toggle
                    if !viewModel.closedDirectories.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.showClosedProjects.toggle()
                            }
                        } label: {
                            Label(
                                viewModel.showClosedProjects ? "Hide Closed" : "Show Closed",
                                systemImage: viewModel.showClosedProjects ? "eye.slash" : "eye"
                            )
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }

                    // Support the Developer
                    Button {
                        showTipJar = true
                    } label: {
                        Label("Support the Developer", systemImage: "heart")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Support the developer, opens tip options")
                }
            } header: {
                HStack {
                    sectionHeader("Projects")
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.Colors.cyberBlue)
                    }
                }
            }

            // MARK: Settings
            Section {
                Button {
                    openSettings()
                } label: {
                    settingsRow(icon: "gearshape", color: Theme.Colors.cyberBlue, title: "Settings")
                }
                .buttonStyle(.plain)
            } header: {
                sectionHeader("Settings")
            }
        }
        .refreshable {
            await viewModel.loadSessions()
            await viewModel.loadStatuses()
            await viewModel.loadProjects()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if connectionManager.activeAPIClient != nil {
                    RefreshButton {
                        await viewModel.loadSessions()
                        await viewModel.loadStatuses()
                        await viewModel.loadProjects()
                    }

                    Button("New Session", systemImage: "plus") {
                        showCreateSheet = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .sheet(isPresented: $showTipJar) {
            NavigationStack {
                TipJarView()
            }
        }
        .projectRenameAlert($renamingProject, viewModel: viewModel)
    }

    // MARK: - Server Switcher Row

    @ViewBuilder
    private var serverSwitcherRow: some View {
        Menu {
            if serverStore.servers.isEmpty {
                Text("No Servers Configured")
                    .foregroundStyle(Theme.Colors.silver)
            } else {
                ForEach(serverStore.servers) { server in
                    Button {
                        connectionManager.connectAndActivate(server: server)
                    } label: {
                        let isActive = server.id == connectionManager.activeServerID
                        Label {
                            HStack {
                                Text(server.name)
                                Spacer()
                                if isActive {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colors.cyberBlue)
                                }
                            }
                        } icon: {
                            Image(systemName: "server.rack")
                                .foregroundStyle(statusColor(for: server))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(activeStatusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: activeStatusColor.opacity(0.6), radius: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeServerName)
                        .font(Theme.Fonts.bodyBold)
                        .foregroundStyle(Theme.Colors.cloud)
                        .lineLimit(1)
                    Text(activeServerDetail)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.silver)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Settings Row

    private func settingsRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.cloud)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.captionBold)
            .foregroundStyle(Theme.Colors.silver)
            .textCase(nil)
    }

    private var activeServerName: String {
        guard let id = connectionManager.activeServerID else { return "No Server" }
        return serverStore.servers.first { $0.id == id }?.name ?? "No Server"
    }

    private var activeServerDetail: String {
        guard let id = connectionManager.activeServerID else { return "Tap to select" }
        let state = connectionManager.connectionState(for: id)
        switch state {
        case .connected: return "Connected"
        case .connecting, .reconnecting: return "Connecting..."
        case .disconnected(let error): return error != nil ? "Error" : "Disconnected"
        case .idle: return "Idle"
        case .offline: return "Offline"
        }
    }

    private var activeStatusColor: Color {
        guard let id = connectionManager.activeServerID else { return ConnectionStatus.idle.color }
        return connectionManager.connectionState(for: id).displayStatus.color
    }

    private func statusColor(for server: ServerConnection) -> Color {
        connectionManager.connectionState(for: server.id).displayStatus.color
    }
}
