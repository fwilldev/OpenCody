//
//  iPadSidebarView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// iPad sidebar with server switcher, live session list, and settings links.
struct iPadSidebarView: View {
    let connectionManager: ConnectionManager
    @Binding var selectedSessionID: String?
    @Binding var showCreateSheet: Bool

    @State private var viewModel: DashboardViewModel
    @EnvironmentObject private var serverStore: ServerStoreModel
    @State private var expandedProjects: Set<String> = []

    // MARK: - Init

    init(
        connectionManager: ConnectionManager,
        selectedSessionID: Binding<String?>,
        showCreateSheet: Binding<Bool>
    ) {
        self.connectionManager = connectionManager
        self._selectedSessionID = selectedSessionID
        self._showCreateSheet = showCreateSheet
        self._viewModel = State(initialValue: DashboardViewModel(connectionManager: connectionManager))
    }

    // MARK: - Body

    var body: some View {
        List(selection: $selectedSessionID) {
            // MARK: Server Switcher
            Section {
                serverSwitcherRow
            } header: {
                sectionHeader("Server")
            }
            .listRowBackground(glassRowBackground)

            // MARK: Sessions
            Section {
                if connectionManager.activeAPIClient == nil {
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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.lg)
                } else if viewModel.sessions.isEmpty && !viewModel.isLoading {
                    Text("No sessions")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                } else {
                    ForEach(sessionsByProject, id: \.key) { project in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedProjects.contains(project.key) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedProjects.insert(project.key)
                                    } else {
                                        expandedProjects.remove(project.key)
                                    }
                                }
                            )
                        ) {
                            ForEach(project.sessions) { session in
                                iPadSessionRow(session: session)
                                    .tag(session.id)
                            }
                            .onDelete { offsets in
                                deleteSessionsInGroup(project.sessions, at: offsets)
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.Colors.cyberBlue)
                                Text(project.key)
                                    .font(Theme.Fonts.bodyBold)
                                    .foregroundStyle(Theme.Colors.cloud)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(project.sessions.count)")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.silver)
                            }
                        }
                        .tint(Theme.Colors.silver)
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
                NavigationLink(value: iPadSettingsDestination.servers) {
                    settingsRow(icon: "server.rack", color: Theme.Colors.cyberBlue, title: "Servers")
                }
                NavigationLink(value: iPadSettingsDestination.providers) {
                    settingsRow(icon: "cpu", color: Theme.Colors.neonGreen, title: "Providers")
                }
                NavigationLink(value: iPadSettingsDestination.mcp) {
                    settingsRow(icon: "puzzlepiece.extension", color: Theme.Colors.electricPurple, title: "MCP Servers")
                }
                NavigationLink(value: iPadSettingsDestination.serverConfig) {
                    settingsRow(icon: "gearshape.2", color: Theme.Colors.neonOrange, title: "Server Config")
                }
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
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.Colors.cyberBlue)
                    }
                }
            }
        }
        .refreshable {
            await viewModel.loadSessions()
            await viewModel.loadStatuses()
        }
        .task {
            await viewModel.loadSessions()
            await viewModel.loadStatuses()
            viewModel.startObservingEvents()
            // Expand all projects by default
            expandedProjects = Set(sessionsByProject.map(\.key))
        }
        .onChange(of: viewModel.sessions) {
            // Auto-expand any new projects
            let allKeys = Set(sessionsByProject.map(\.key))
            let newKeys = allKeys.subtracting(expandedProjects)
            expandedProjects.formUnion(newKeys)
        }
        .onDisappear {
            viewModel.stopObservingEvents()
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
                        connectionManager.setActiveServer(server.id)
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

    // MARK: - Session Row

    private func iPadSessionRow(session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title.isEmpty ? "Untitled Session" : session.title)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.cloud)
                    .lineLimit(1)

                Spacer()

                if isSessionRunning(status: viewModel.statusMap[session.id]) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Colors.cyberBlue)
                }

                statusDot(for: viewModel.statusMap[session.id])
            }

            Text(session.directory)
                .font(Theme.Fonts.codeCaption)
                .foregroundStyle(Theme.Colors.silver)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: Theme.Spacing.xs) {
                if let summary = session.summary {
                    Text("+\(summary.additions)")
                        .font(Theme.Fonts.codeCaption)
                        .foregroundStyle(Theme.Colors.neonGreen.opacity(0.8))
                    Text("-\(summary.deletions)")
                        .font(Theme.Fonts.codeCaption)
                        .foregroundStyle(Theme.Colors.hotPink.opacity(0.8))
                }

                Spacer()

                Text(relativeTime(for: session))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.smoke)
            }
        }
        .padding(.vertical, 4)
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
        }
    }

    private var activeStatusColor: Color {
        guard let id = connectionManager.activeServerID else { return ConnectionStatus.idle.color }
        return connectionStatusFrom(connectionManager.connectionState(for: id)).color
    }

    private func statusColor(for server: ServerConnection) -> Color {
        connectionStatusFrom(connectionManager.connectionState(for: server.id)).color
    }

    private func statusDot(for status: SessionStatus?) -> some View {
        let connStatus: ConnectionStatus = {
            guard let status else { return .idle }
            switch status {
            case .idle: return .idle
            case .busy: return .active
            case .retry: return .connecting
            }
        }()
        return Circle()
            .fill(connStatus.color)
            .frame(width: 7, height: 7)
            .shadow(color: connStatus.color.opacity(0.5), radius: 2)
    }

    private func isSessionRunning(status: SessionStatus?) -> Bool {
        guard let status else { return false }
        switch status {
        case .idle:
            return false
        case .busy, .retry:
            return true
        }
    }

    private func relativeTime(for session: Session) -> String {
        let date = Date(timeIntervalSince1970: session.time.updated)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func connectionStatusFrom(_ state: ConnectionState) -> ConnectionStatus {
        switch state {
        case .connected: return .active
        case .connecting, .reconnecting: return .connecting
        case .disconnected(let error): return error != nil ? .error : .idle
        case .idle: return .idle
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = viewModel.sessions[index]
            Task {
                try? await viewModel.deleteSession(id: session.id)
            }
        }
    }

    private func deleteSessionsInGroup(_ sessions: [Session], at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            Task {
                try? await viewModel.deleteSession(id: session.id)
            }
        }
    }

    private var sessionsByProject: [(key: String, sessions: [Session])] {
        let grouped = Dictionary(grouping: viewModel.sessions) { session -> String in
            let components = session.directory
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/")
            return components.last.map(String.init) ?? session.directory
        }
        return grouped
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { (key: $0.key, sessions: $0.value.sorted { $0.time.updated > $1.time.updated }) }
    }
}

/// Navigation destinations for settings items in the iPad sidebar.
enum iPadSettingsDestination: Hashable {
    case servers
    case providers
    case mcp
    case serverConfig
}
