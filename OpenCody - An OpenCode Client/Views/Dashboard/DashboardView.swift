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
    @EnvironmentObject private var serverStore: ServerStoreModel

    // MARK: - Init

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        self._viewModel = State(initialValue: DashboardViewModel(connectionManager: connectionManager))
    }

    // MARK: - Computed

    /// Sessions grouped by the last component of their directory path (i.e. project folder name).
    private var sessionsByProject: [(key: String, sessions: [Session])] {
        let grouped = Dictionary(grouping: viewModel.sessions) { session -> String in
            // Use the last path component as the project name; fall back to full path
            let components = session.directory
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/")
            return components.last.map(String.init) ?? session.directory
        }
        return grouped
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { (key: $0.key, sessions: $0.value.sorted { $0.time.updated > $1.time.updated }) }
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
                if connectionManager.activeAPIClient == nil && !serverStore.servers.isEmpty {
                    // Server is connecting — show skeleton while we wait
                    loadingSkeleton
                } else if viewModel.isLoading && viewModel.sessions.isEmpty {
                    loadingSkeleton
                } else if viewModel.sessions.isEmpty && !viewModel.isLoading {
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
                connectionManager: connectionManager
            )
        }
        .sheet(isPresented: $showAddServer) {
            NavigationStack {
                AddServerView(connectionManager: connectionManager)
                    .environmentObject(serverStore)
            }
        }
        .task(id: connectionManager.activeServerID) {
            await viewModel.loadSessions()
            await viewModel.loadStatuses()
            viewModel.startObservingEvents()
        }
        .onDisappear {
            viewModel.stopObservingEvents()
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    // MARK: - Helpers

    private func connectionStatusFrom(_ state: ConnectionState) -> ConnectionStatus {
        switch state {
        case .connected:
            return .active
        case .connecting:
            return .connecting
        case .reconnecting:
            return .connecting
        case .disconnected(let error):
            return error != nil ? .error : .idle
        case .idle:
            return .idle
        }
    }

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
