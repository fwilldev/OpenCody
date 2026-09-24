//
//  ProjectSessionsView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 26.02.26.
//

import SwiftUI

// MARK: - ProjectSessionsView

/// Displays the list of sessions for a specific project, with navigation to chat.
/// Fetches sessions per-directory with `roots=true` so that summary data and diffs are available.
/// Subscribes to SSE events for live session/status updates.
struct ProjectSessionsView: View {
    let projectName: String
    let projectPath: String?
    let initialStatusMap: [String: SessionStatus]
    let viewModel: DashboardViewModel
    let connectionManager: ConnectionManager

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showCreateSheet: Bool = false
    @State private var createdSession: Session?
    @State private var projectSessions: [Session] = []
    @State private var localStatusMap: [String: SessionStatus] = [:]
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var eventToken: UUID? = nil
    @State private var refreshToken: UUID? = nil
    @State private var displayLimit: Int = 5
    @State private var hasMore: Bool = false
    @State private var showArchived: Bool = false

    /// OpenCode 2.x cannot archive sessions, so its archive controls are hidden.
    private var supportsArchiving: Bool {
        connectionManager.activeAPIClient?.supportsSessionArchiving ?? true
    }

    /// Sessions filtered by archive status.
    private var visibleSessions: [Session] {
        if showArchived {
            return projectSessions
        }
        return projectSessions.filter { $0.time.archived == nil }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.deepBlack
                .ignoresSafeArea()

            if isLoading && projectSessions.isEmpty {
                ProgressView("Loading sessions…")
                    .tint(Theme.Colors.cyberBlue)
                    .foregroundStyle(Theme.Colors.silver)
            } else if visibleSessions.isEmpty {
                EmptyStateView(
                    systemImage: "rectangle.stack",
                    title: "No Sessions",
                    message: showArchived
                        ? "This project has no sessions yet."
                        : "No active sessions. Tap the archive filter to see archived ones."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(visibleSessions) { session in
                            sessionRow(session)
                        }

                        // Show More button
                        if hasMore {
                            Button {
                                Task {
                                    await loadMoreSessions()
                                }
                            } label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text("Show More")
                                        .font(Theme.Fonts.bodyBold)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(Theme.Colors.cyberBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.Colors.cyberBlue.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Theme.Colors.cyberBlue.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .navigationTitle(projectName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Theme.Spacing.sm) {
                    if supportsArchiving {
                        Button {
                            showArchived.toggle()
                        } label: {
                            Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                                .foregroundStyle(showArchived ? Theme.Colors.hotPink : Theme.Colors.silver)
                        }
                    }

                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.Colors.cyberBlue)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                RefreshButton {
                    displayLimit = 5
                    await loadProjectSessions()
                    await loadStatuses()
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSessionSheet(
                viewModel: viewModel,
                connectionManager: connectionManager,
                preselectedPath: projectPath,
                onSessionCreated: { session in
                    createdSession = session
                }
            )
            .presentationDetents([.large])
        }
        .navigationDestination(item: $createdSession) { session in
            chatDestination(for: session)
        }
        .task(id: projectPath) {
            stopObservingEvents()
            localStatusMap = initialStatusMap
            projectSessions = []
            isLoading = true
            loadError = nil
            displayLimit = 5
            hasMore = false
            await loadProjectSessions()
            await loadStatuses()
            startObservingEvents()
        }
        .onDisappear {
            stopObservingEvents()
        }
    }

    // MARK: - Data Loading

    private func loadProjectSessions() async {
        guard let client = connectionManager.activeAPIClient,
              let rawPath = projectPath else {
            isLoading = false
            return
        }

        let directory = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"

        isLoading = true
        loadError = nil

        do {
            let api = SessionAPI(client: client, directory: directory)
            // Fetch one extra to detect if there are more sessions beyond the display limit.
            let fetched = try await api.list(roots: true, limit: displayLimit + 1)
            hasMore = fetched.count > displayLimit
            let limited = hasMore ? Array(fetched.prefix(displayLimit)) : fetched
            projectSessions = limited.sorted { $0.time.updated > $1.time.updated }
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    /// Load more sessions by increasing the display limit.
    private func loadMoreSessions() async {
        displayLimit += 5
        await loadProjectSessions()
    }

    private func loadStatuses() async {
        guard let client = connectionManager.activeAPIClient else { return }
        let api = SessionAPI(client: client)
        if let map = try? await api.status() {
            localStatusMap = map
        }
    }

    // MARK: - SSE Event Observation

    private func startObservingEvents() {
        eventToken = connectionManager.subscribeToEvents { event in
            handleEvent(event)
        }
        refreshToken = connectionManager.subscribeToRefresh {
            Task {
                await loadProjectSessions()
                await loadStatuses()
            }
        }
    }

    private func stopObservingEvents() {
        if let t = eventToken { connectionManager.unsubscribeFromEvents(token: t) }
        if let t = refreshToken { connectionManager.unsubscribeFromRefresh(token: t) }
        eventToken = nil
        refreshToken = nil
    }

    private func handleEvent(_ event: SSEEvent) {
        guard let rawPath = projectPath else { return }
        let directory = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"

        switch event {
        case .sessionCreated(let session):
            guard session.directory == directory else { return }
            if !projectSessions.contains(where: { $0.id == session.id }) {
                projectSessions.insert(session, at: 0)
            }

        case .sessionUpdated(let session):
            guard session.directory == directory else { return }
            if let index = projectSessions.firstIndex(where: { $0.id == session.id }) {
                projectSessions[index] = session
            } else {
                projectSessions.insert(session, at: 0)
            }

        case .sessionDeleted(let session):
            projectSessions.removeAll { $0.id == session.id }
            localStatusMap.removeValue(forKey: session.id)

        case .sessionStatus(let payload):
            // Update status for any session we're tracking
            if projectSessions.contains(where: { $0.id == payload.sessionID }) {
                localStatusMap[payload.sessionID] = payload.status
            }

        case .sessionIdle(let sessionID):
            if projectSessions.contains(where: { $0.id == sessionID }) {
                localStatusMap[sessionID] = .idle
            }

        default:
            break
        }
    }

    /// One session row: the card, its navigation link, and its context menu.
    ///
    /// Extracted from `body` because inlining it pushed the enclosing expression
    /// past the type-checker's time limit.
    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        NavigationLink(destination: chatDestination(for: session)) {
            SessionCardView(
                session: session,
                status: localStatusMap[session.id],
                connectionManager: connectionManager
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !supportsArchiving {
                EmptyView()
            } else if session.time.archived != nil {
                Button {
                    Task { await setArchived(session, archived: false) }
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    Task { await setArchived(session, archived: true) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }

            Button(role: .destructive) {
                Task {
                    try? await viewModel.deleteSession(id: session.id)
                    projectSessions.removeAll { $0.id == session.id }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Archive or unarchive a session, mirroring the result back into the local list.
    private func setArchived(_ session: Session, archived: Bool) async {
        if archived {
            try? await viewModel.archiveSession(id: session.id)
        } else {
            try? await viewModel.unarchiveSession(id: session.id)
        }
        if let index = projectSessions.firstIndex(where: { $0.id == session.id }),
           let updated = viewModel.sessions.first(where: { $0.id == session.id }) {
            projectSessions[index] = updated
        }
    }

    @ViewBuilder
    private func chatDestination(for session: Session) -> some View {
        if sizeClass == .compact {
            ChatView(session: session, connectionManager: connectionManager)
        } else {
            iPadChatUtilitiesContainer(session: session, connectionManager: connectionManager)
        }
    }
}

// MARK: - iPad Chat Utilities Container

private struct iPadChatUtilitiesContainer: View {
    let session: Session
    let connectionManager: ConnectionManager

    @State private var viewModel: ChatViewModel
    @State private var isUtilitiesOpen = false
    @State private var selectedTab: iPadUtilityTab = .files

    init(session: Session, connectionManager: ConnectionManager) {
        self.session = session
        self.connectionManager = connectionManager
        self._viewModel = State(initialValue: ChatViewModel(session: session, connectionManager: connectionManager))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ChatView(
                session: session,
                connectionManager: connectionManager,
                viewModel: viewModel,
                utilitiesState: iPadUtilitiesState(isOpen: $isUtilitiesOpen, selectedTab: $selectedTab)
            )

            if isUtilitiesOpen {
                utilitiesOverlay
            }
        }
    }

    @ViewBuilder
    private var utilitiesOverlay: some View {
        if let client = connectionManager.activeAPIClient {
            HStack(spacing: 0) {
                Color.black.opacity(0.25)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isUtilitiesOpen = false
                        }
                    }

                iPadUtilitiesPanel(
                    session: session,
                    apiClient: client,
                    viewModel: viewModel,
                    selectedTab: $selectedTab
                )
                .frame(width: 360)
                .transition(.move(edge: .trailing))
            }
            .ignoresSafeArea(.container, edges: [.bottom, .trailing])
        }
    }
}
