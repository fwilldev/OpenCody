import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    @State private var connectionManager: ConnectionManager
    @StateObject private var serverStore = ServerStoreModel()
    /// Shared by both layouts, so a resize keeps the loaded projects.
    @State private var dashboardViewModel: DashboardViewModel

    @State private var notificationManager: SessionNotificationManager

    /// Release notes, shown once per release.
    @State private var showWhatsNew = false

    init() {
        let connectionManager = ConnectionManager()
        let router = AppRouter()
        _router = State(initialValue: router)
        _connectionManager = State(initialValue: connectionManager)
        _notificationManager = State(initialValue: SessionNotificationManager(connectionManager: connectionManager, router: router))
        _dashboardViewModel = State(initialValue: DashboardViewModel(connectionManager: connectionManager))
    }

    var body: some View {
        @Bindable var router = router
        layout
        .background(Theme.Colors.deepBlack)
        .onChange(of: scenePhase) { _, newPhase in
            connectionManager.handleScenePhaseChange(newPhase)
            if newPhase == .background {
                BackgroundRefreshService.shared.scheduleAppRefresh()
            } else if newPhase == .active {
                KeychainService.allowBackgroundAccess()
                Task { await notificationManager.becameActive() }
            }
        }
        .onChange(of: router.selectedSession) { _, sessionID in
            guard let sessionID else { return }
            Task { await notificationManager.markViewed(sessionID) }
        }
        .onChange(of: NotificationDelegate.shared.pendingLink, initial: true) { _, link in
            guard let link else { return }
            NotificationDelegate.shared.pendingLink = nil
            Task { await open(link) }
        }
        .task(id: serverStore.servers.first?.id) {
            // Auto-connect to the first saved server on launch
            guard connectionManager.activeServerID == nil, let first = serverStore.servers.first else { return }
            connectionManager.connectAndActivate(server: first)
        }
        .task {
            serverStore.load()

            if WhatsNew.isPending() {
                showWhatsNew = true
                WhatsNew.markSeen()
            }

            // Record app launch for tip / rating prompt eligibility tracking.
            PromptEngagement.recordLaunch()

            // Verify has-tipped state against StoreKit transaction history
            // so reinstalls don't re-prompt users who already supported.
            await TipPromptService.shared.refreshHasTippedFromStoreKit()

            NotificationDelegate.shared.viewingSessionID = { [router] in router.selectedSession }
            notificationManager.startObserving()
            // A cold launch can be active before the scene phase changes.
            KeychainService.allowBackgroundAccess()
            await notificationManager.becameActive()
        }
        .onDisappear {
            notificationManager.stopObserving()
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .sheet(item: $router.newSession) { request in
            CreateSessionSheet(
                viewModel: dashboardViewModel,
                connectionManager: connectionManager,
                preselectedPath: request.directory,
                onSessionCreated: router.openChat
            )
        }
        .sheet(isPresented: $router.showAddServer) {
            ServerFormView(server: nil, connectionManager: connectionManager)
                .environmentObject(serverStore)
        }
        .sheet(isPresented: $router.showTipJar) {
            NavigationStack {
                TipJarView()
            }
        }
        .environment(router)
        .environmentObject(serverStore)
    }

    /// Opens a tapped notification's session, switching server if needed.
    private func open(_ link: DeepLink) async {
        guard let server = ServerStore.shared.load().first(where: { $0.id == link.serverID }) else { return }
        connectionManager.connectAndActivate(server: server)
        guard let session = try? await SessionAPI(client: server.makeAPIClient()).get(id: link.sessionID) else { return }
        router.openChat(session)
    }

    /// Compact width gets the tab bar, regular width the sidebar. This follows the
    /// window, not the device: iPhone Duo's inner display and wide iPad windows are
    /// regular, its outer display and narrow Split View windows are compact.
    @ViewBuilder
    private var layout: some View {
        @Bindable var router = router
        if sizeClass == .compact {
            TabView(selection: $router.selectedTab) {
                Tab("Dashboard", systemImage: "rectangle.stack", value: AppRouter.TabItem.dashboard) {
                    NavigationStack(path: $router.dashboardPath) {
                        DashboardView(viewModel: dashboardViewModel, connectionManager: connectionManager)
                            .navigationDestination(for: AppRouter.Route.self) { route in
                                switch route {
                                case .project(let directory):
                                    ProjectSessionsView(
                                        projectPath: directory,
                                        viewModel: dashboardViewModel,
                                        connectionManager: connectionManager
                                    )
                                case .chat(let session):
                                    ChatView(session: session, connectionManager: connectionManager)
                                }
                            }
                    }
                }
                Tab("Settings", systemImage: "gearshape", value: AppRouter.TabItem.settings) {
                    NavigationStack(path: $router.settingsPath) {
                        SettingsView(connectionManager: connectionManager)
                    }
                }
            }
            .tint(Theme.Colors.cyberBlue)
        } else {
            SplitRootView(viewModel: dashboardViewModel, connectionManager: connectionManager)
        }
    }
}
