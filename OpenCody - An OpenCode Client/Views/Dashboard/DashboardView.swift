//
//  DashboardView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI

// MARK: - DashboardView

/// Main dashboard showing the list of projects, with drill-down to sessions and real-time updates via SSE.
struct DashboardView: View {
    let connectionManager: ConnectionManager
    @State private var viewModel: DashboardViewModel
    @State private var showCreateSheet: Bool = false
    @State private var showAddServer: Bool = false
    @State private var showTipJar: Bool = false
    @State private var createdSession: Session?
    @EnvironmentObject private var serverStore: ServerStoreModel

    /// Tracks how many times this view has appeared during the current app session.
    /// A count > 1 means the user navigated away (e.g. into a chat) and came back —
    /// which is the "natural moment" for the occasional tip prompt.
    @State private var viewAppearCount = 0
    @Bindable private var tipPromptService = TipPromptService.shared

    // MARK: - Init

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        self._viewModel = State(initialValue: DashboardViewModel(connectionManager: connectionManager))
    }

    // MARK: - Computed

    /// Whether the active server's connection is in the offline state.
    private var isActiveServerOffline: Bool {
        guard let id = connectionManager.activeServerID else { return false }
        return connectionManager.connectionState(for: id) == .offline
    }

    /// Sessions grouped by the last component of their directory path (i.e. project folder name).
    private var sessionsByProject: [(key: String, sessions: [Session], directory: String)] {
        let grouped = Dictionary(grouping: viewModel.activeSessions) { session -> String in
            // Use the last path component as the project name; fall back to full path
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

    /// Whether there are any closed projects to potentially show.
    private var hasClosedProjects: Bool {
        !viewModel.closedDirectories.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Theme.Colors.deepBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Error banner
                if let errorMessage = viewModel.error {
                    ErrorBanner(
                        error: .network(errorMessage),
                        onDismiss: { viewModel.error = nil }
                    )
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                }

                // Content
                if isActiveServerOffline {
                    offlineState
                } else if connectionManager.activeAPIClient == nil && !serverStore.servers.isEmpty {
                    // Server is connecting — show skeleton while we wait
                    loadingSkeleton
                } else if viewModel.isLoading && viewModel.activeSessions.isEmpty {
                    loadingSkeleton
                } else if viewModel.activeSessions.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    projectList
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ServerSwitcherView(
                    servers: serverStore.servers,
                    connectionManager: connectionManager
                )
            }

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
        .sheet(isPresented: $showCreateSheet) {
            CreateSessionSheet(
                viewModel: viewModel,
                connectionManager: connectionManager,
                onSessionCreated: { session in
                    createdSession = session
                }
            )
        }
        .navigationDestination(item: $createdSession) { session in
            ChatView(session: session, connectionManager: connectionManager)
        }
        .sheet(isPresented: $showAddServer) {
            NavigationStack {
                AddServerView(connectionManager: connectionManager)
                    .environmentObject(serverStore)
            }
        }
        .task(id: connectionManager.activeServerID) {
            viewModel.loadClosedProjects()
            await viewModel.loadSessions()
            await viewModel.loadStatuses()
            viewModel.startObservingEvents()
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
        .onDisappear {
            viewModel.stopObservingEvents()
        }
        .sheet(isPresented: $showTipJar) {
            NavigationStack {
                TipJarView()
            }
        }
        .onAppear {
            viewAppearCount += 1
            // Only consider showing the prompt when returning to the dashboard
            // after navigating away (e.g. after closing a chat), never on first display.
            if viewAppearCount > 1 && tipPromptService.shouldShowPrompt {
                tipPromptService.recordPromptShown()
                tipPromptService.showPrompt = true
            }
        }
        .alert("Enjoying OpenCody?", isPresented: $tipPromptService.showPrompt) {
            Button("Sure, show me") {
                showTipJar = true
            }
            Button("Maybe later", role: .cancel) { }
        } message: {
            Text("This app is a solo project and stays free and ad-free. If it's been useful to you, a small tip would mean a lot and helps keep development going.")
        }
    }

    // MARK: - Subviews

    /// Skeleton loading state — shown while the first load is in progress.
    private var loadingSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonCard()
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .allowsHitTesting(false)
    }

    /// Offline state — shown when the server connection has been marked offline after max retries.
    private var offlineState: some View {
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
    }

    /// Empty state when no sessions or no server connected.
    private var emptyState: some View {
        Group {
            if connectionManager.activeAPIClient == nil {
                EmptyStateView(
                    systemImage: "server.rack",
                    title: "No Server Connected",
                    message: "Add a server in Settings to get started.",
                    action: { showAddServer = true },
                    actionLabel: "Add Server"
                )
            } else {
                EmptyStateView(
                    systemImage: "rectangle.stack",
                    title: "No Sessions",
                    message: "Start a new coding session",
                    action: { showCreateSheet = true },
                    actionLabel: "New Session"
                )
            }
        }
    }

    /// Scrollable list of project cards, each linking to sessions for that project.
    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(sessionsByProject, id: \.key) { group in
                    let isClosed = viewModel.isProjectClosed(directory: group.directory)

                    NavigationLink(destination: ProjectSessionsView(
                        projectName: group.key,
                        projectPath: group.sessions.first?.directory,
                        initialStatusMap: viewModel.statusMap,
                        viewModel: viewModel,
                        connectionManager: connectionManager
                    )) {
                        ProjectCardView(
                            projectName: group.key,
                            activeSessions: group.sessions.filter { isBusy(viewModel.statusMap[$0.id]) }.count,
                            lastUpdated: group.sessions.first?.time.updated ?? 0
                        )
                        .opacity(isClosed ? 0.5 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if isClosed {
                            Button {
                                withAnimation { viewModel.reopenProject(directory: group.directory) }
                            } label: {
                                Label("Reopen Project", systemImage: "eye")
                            }
                        } else {
                            Button {
                                withAnimation { viewModel.closeProject(directory: group.directory) }
                            } label: {
                                Label("Close Project", systemImage: "eye.slash")
                            }
                        }
                    }
                }

                // Show/hide closed projects toggle
                if hasClosedProjects {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.showClosedProjects.toggle()
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: viewModel.showClosedProjects ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.Colors.smoke)
                            Text(viewModel.showClosedProjects ? "Hide Closed Projects" : "Show Closed Projects")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.smoke)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                    }
                    .buttonStyle(.plain)
                }

                // Support the Developer footer link
                Button {
                    showTipJar = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart")
                            .font(.system(size: 11))
                        Text("Support the Developer")
                            .font(.footnote)
                    }
                    .foregroundStyle(Theme.Colors.smoke)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Support the developer, opens tip options")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    // MARK: - Helpers

    /// Check if a session status is busy (SessionStatus doesn't conform to Equatable).
    private func isBusy(_ status: SessionStatus?) -> Bool {
        guard let status else { return false }
        if case .busy = status { return true }
        return false
    }
}

// MARK: - SkeletonCard

private struct SkeletonCard: View {
    @State private var shimmer: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 160, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 10)
                    .fill(shimmerGradient)
                    .frame(width: 50, height: 20)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerGradient)
                .frame(width: 220, height: 11)
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 120, height: 11)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 50, height: 11)
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard()
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { shimmer = true } }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(shimmer ? 0.10 : 0.04),
                Color.white.opacity(shimmer ? 0.04 : 0.10)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
