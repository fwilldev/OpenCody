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
    @State private var isLoadingMore = false
    @State private var loadError: String? = nil
    @State private var eventToken: UUID? = nil
    @State private var refreshToken: UUID? = nil
    /// Cursor of the next page; `nil` when everything is loaded.
    @State private var nextCursor: String?
    @State private var searchText = ""
    @State private var showArchived: Bool = false
    @State private var renamingSession: Session?
    @State private var deletingSession: Session?

    private let pageSize = 20

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

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    if isLoading && projectSessions.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in SkeletonCard() }
                            .accessibilityHidden(true)
                    } else if let loadError, projectSessions.isEmpty {
                        EmptyStateView(
                            systemImage: "wifi.exclamationmark",
                            title: "Couldn't Load Sessions",
                            message: loadError,
                            action: { Task { await reload() } },
                            actionLabel: "Try Again"
                        )
                    } else if visibleSessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleSessions) { session in
                            sessionRow(session)
                                .transition(.opacity)
                        }

                        if nextCursor != nil {
                            Button {
                                Task { await loadMoreSessions() }
                            } label: {
                                if isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Show More", systemImage: "chevron.down")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .secondaryButton()
                            .disabled(isLoadingMore)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .animation(.default, value: visibleSessions.map(\.id))
            }
            .refreshable { await reload() }

            if let loadError, !projectSessions.isEmpty {
                ErrorBanner(error: .network(loadError), onDismiss: { self.loadError = nil })
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .navigationTitle(projectPath.map(viewModel.projectName(for:)) ?? projectName)
        .searchable(text: $searchText, prompt: "Search sessions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if supportsArchiving {
                    Toggle("Show Archived", systemImage: showArchived ? "archivebox.fill" : "archivebox", isOn: $showArchived)
                        .toggleStyle(.button)
                }

                RefreshButton { await reload() }

                Button("New Session", systemImage: "plus") {
                    showCreateSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
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
        .renameAlert(
            "Rename Session",
            item: $renamingSession,
            currentName: { $0.title },
            onSave: { session, title in Task { await rename(session, to: title) } }
        )
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(get: { deletingSession != nil }, set: { if !$0 { deletingSession = nil } }),
            titleVisibility: .visible,
            presenting: deletingSession
        ) { session in
            Button("Delete Session", role: .destructive) {
                Task { await delete(session) }
            }
        } message: { session in
            Text("“\(session.title.isEmpty ? "Untitled Session" : session.title)” and its messages will be removed from the server.")
        }
        .task(id: projectPath) {
            stopObservingEvents()
            localStatusMap = initialStatusMap
            projectSessions = []
            isLoading = true
            await reload()
            startObservingEvents()
        }
        .task(id: searchText) {
            guard !isLoading || !projectSessions.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await loadProjectSessions()
        }
        .onDisappear {
            stopObservingEvents()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            EmptyStateView(
                systemImage: "rectangle.stack",
                title: "No Sessions",
                message: showArchived || !supportsArchiving
                    ? "This project has no sessions yet."
                    : "No active sessions. Use the archive button to see archived ones.",
                action: { showCreateSheet = true },
                actionLabel: "New Session"
            )
        }
    }

    // MARK: - Data Loading

    private var directory: String? {
        projectPath.map { $0.hasPrefix("/") ? $0 : "/\($0)" }
    }

    private func reload() async {
        await loadProjectSessions()
        await loadStatuses()
    }

    /// Load the first page, replacing what is shown.
    private func loadProjectSessions() async {
        guard let client = connectionManager.activeAPIClient, let directory else {
            isLoading = false
            return
        }

        isLoading = true
        loadError = nil

        do {
            let page = try await SessionAPI(client: client, directory: directory)
                .page(limit: pageSize, search: searchText)
            projectSessions = page.sessions
            nextCursor = page.next
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    /// Append the next page.
    private func loadMoreSessions() async {
        guard let client = connectionManager.activeAPIClient, let directory, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await SessionAPI(client: client, directory: directory)
                .page(limit: pageSize, cursor: cursor, search: searchText)
            let known = Set(projectSessions.map(\.id))
            projectSessions += page.sessions.filter { !known.contains($0.id) }
            nextCursor = page.next
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ session: Session) async {
        do {
            try await viewModel.deleteSession(id: session.id)
            withAnimation { projectSessions.removeAll { $0.id == session.id } }
        } catch {
            loadError = "Couldn't delete the session: \(error.localizedDescription)"
        }
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
        .hoverEffect(.highlight)
        .contextMenu {
            Button("Rename Session", systemImage: "pencil") {
                renamingSession = session
            }

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

            Button("Delete", systemImage: "trash", role: .destructive) {
                deletingSession = session
            }
        }
    }

    private func rename(_ session: Session, to title: String) async {
        guard let index = projectSessions.firstIndex(where: { $0.id == session.id }) else { return }
        projectSessions[index] = session.retitled(title)
        do {
            let updated = try await viewModel.renameSession(session, to: title)
            if let i = projectSessions.firstIndex(where: { $0.id == session.id }) { projectSessions[i] = updated }
        } catch {
            if let i = projectSessions.firstIndex(where: { $0.id == session.id }) { projectSessions[i] = session }
            loadError = "Couldn't rename the session: \(error.localizedDescription)"
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
