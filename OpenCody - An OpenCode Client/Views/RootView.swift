import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    @State private var connectionManager = ConnectionManager()
    @State private var notificationStore = NotificationStore()
    @StateObject private var serverStore = ServerStoreModel()

    /// Notification manager — created lazily once dependencies are available.
    @State private var notificationManager: SessionNotificationManager?

    var body: some View {
        Group {
            if sizeClass == .compact {
                TabView(selection: $router.selectedTab) {
                    Tab("Dashboard", systemImage: "rectangle.stack", value: AppRouter.TabItem.dashboard) {
                        NavigationStack(path: $router.dashboardPath) {
                            DashboardView(connectionManager: connectionManager)
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
                iPadRootView(router: router, connectionManager: connectionManager)
            }
        }
        .background(Theme.Colors.deepBlack)
        .onChange(of: scenePhase) { _, newPhase in
            connectionManager.handleScenePhaseChange(newPhase)
            if newPhase == .background {
                BackgroundRefreshService.shared.apiClientProvider = { [weak connectionManager] in
                    connectionManager?.activeAPIClient
                }
                BackgroundRefreshService.shared.scheduleAppRefresh()
            } else if newPhase == .active {
                LocalNotificationService.shared.requestAuthorization()
            }
        }
        .task(id: serverStore.servers.first?.id) {
            // Auto-connect to the first saved server on launch
            guard connectionManager.activeServerID == nil, let first = serverStore.servers.first else { return }
            connectionManager.connectAndActivate(server: first)
        }
        .task {
            serverStore.load()

            // Record app launch for tip prompt eligibility tracking.
            TipPromptService.shared.recordAppLaunch()

            // Verify has-tipped state against StoreKit transaction history
            // so reinstalls don't re-prompt users who already supported.
            await TipPromptService.shared.refreshHasTippedFromStoreKit()

            // Start notification observation
            let manager = SessionNotificationManager(
                connectionManager: connectionManager,
                router: router,
                store: notificationStore
            )
            manager.startObserving()
            notificationManager = manager
        }
        .onDisappear {
            notificationManager?.stopObserving()
        }
        .environmentObject(serverStore)
    }
}
