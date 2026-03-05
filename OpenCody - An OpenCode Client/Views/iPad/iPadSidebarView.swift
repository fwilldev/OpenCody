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
    @State private var expandedProjects: Set<String> = []

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
            .listRowBackground(glassRowBackground)

            // MARK: Projects
            Section {
                if isActiveServerOffline {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.Colors.hotPink)
                        Text("Server Offline")
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.cloud)
                        Text("Could not reach server.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                        Button("Reconnect") {
                            guard let id = connectionManager.activeServerID else { return }
                            Task {
                                await connectionManager.retryConnection(for: id)
                            }
                        }
                        .font(Theme.Fonts.captionBold)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.lg)
                } else if connectionManager.activeAPIClient == nil && !serverStore.servers.isEmpty {
                    VStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                            .tint(Theme.Colors.cyberBlue)
                        Text("Connecting…")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.lg)
                } else if connectionManager.activeAPIClient == nil {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.Colors.silver)
                        Text("No Server Connected")
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.cloud)
                        Text("Add a server to get started.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                        Button("Manage Servers") {
                            openServers()
                        }
                        .font(Theme.Fonts.captionBold)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.lg)
                } else if viewModel.activeSessions.isEmpty && !viewModel.isLoading {
                    Text("No sessions")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                } else {
                    ForEach(sessionsByProject, id: \.key) { project in
                        let isClosed = viewModel.isProjectClosed(directory: project.directory)

                        Button {
                            selectedProjectKey = project.key
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.Colors.cyberBlue)
                                Text(project.key)
                                    .font(Theme.Fonts.bodyBold)
                                    .foregroundStyle(Theme.Colors.cloud)
                                    .lineLimit(1)
                            }
                            .opacity(isClosed ? 0.5 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .tag(project.key)
                        .listRowBackground(glassRowBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if isClosed {
                                Button {
                                    withAnimation { viewModel.reopenProject(directory: project.directory) }
                                } label: {
                                    Label("Open", systemImage: "eye")
                                }
                                .tint(Color.blue)
                            } else {
                                Button {
                                    withAnimation { viewModel.closeProject(directory: project.directory) }
                                } label: {
                                    Label("Close", systemImage: "eye.slash")
                                }
                                .tint(.orange)
                            }
                        }
                        .contextMenu {
                            if isClosed {
                                Button {
                                    withAnimation { viewModel.reopenProject(directory: project.directory) }
                                } label: {
                                    Label("Reopen Project", systemImage: "eye")
                                }
                            } else {
                                Button {
                                    withAnimation { viewModel.closeProject(directory: project.directory) }
                                } label: {
                                    Label("Close Project", systemImage: "eye.slash")
                                }
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
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: viewModel.showClosedProjects ? "eye.slash" : "eye")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.Colors.smoke)
                                Text(viewModel.showClosedProjects ? "Hide Closed" : "Show Closed")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.smoke)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
            } header: {
                HStack {
                    sectionHeader("Sessions")
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.Colors.cyberBlue)
                    }
                }
            }
            .listRowBackground(glassRowBackground)

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
            .listRowBackground(glassRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.carbon)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if connectionManager.activeAPIClient != nil {
                    HStack(spacing: Theme.Spacing.sm) {
                        RefreshButton {
                            await viewModel.loadSessions()
                            await viewModel.loadStatuses()
                        }

                        Button {
                            showCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(Theme.Colors.cyberBlue)
                        }
                    }
                }
            }
        }
        .task { }
        .onChange(of: viewModel.sessions) { _, _ in
            // Auto-expand any new projects
            // Keep collapsed by default
        }
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

    // MARK: - Session Row (removed for iPad project list)

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

    private var glassRowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
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

    // MARK: - Session helpers removed

    // MARK: - Delete helpers removed

    private var sessionsByProject: [(key: String, sessions: [Session], directory: String)] {
        let grouped = Dictionary(grouping: viewModel.activeSessions) { session -> String in
            let components = session.directory
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/")
            return components.last.map(String.init) ?? session.directory
        }
        let closed = viewModel.closedDirectories
        return grouped
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { (key: $0.key, sessions: $0.value.sorted { $0.time.updated > $1.time.updated }, directory: $0.value.first?.directory ?? "") }
            .filter { group in
                if viewModel.showClosedProjects { return true }
                return !closed.contains(group.directory)
            }
    }
}
