//
//  BackgroundRefreshService.swift
//  OpenCody - An OpenCode Client
//

import BackgroundTasks
import Foundation

/// Manages BGAppRefreshTask registration and handling.
///
/// A background refresh catches up on OpenCode 2.x servers: finished or failed sessions
/// and open permission requests and questions become notifications.
///
/// Background execution on iOS Simulator is not guaranteed — this is best-effort.
/// The app must declare `BGTaskSchedulerPermittedIdentifiers` in Info.plist and
/// call `registerTasks()` before the app finishes launching.
@MainActor
final class BackgroundRefreshService {

    static let shared = BackgroundRefreshService()
    private init() {}

    // MARK: - Constants

    static let taskIdentifier = "com.opencody.bgrefresh"
    /// Minimum interval between background refreshes (15 minutes).
    private static let minimumFetchInterval: TimeInterval = 15 * 60

    // MARK: - Registration

    /// Register the BGAppRefreshTask handler.
    /// **Must be called before the app finishes launching** (i.e. in the App struct body or init).
    nonisolated func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshService.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await BackgroundRefreshService.shared.handleAppRefresh(refreshTask)
            }
        }
    }

    // MARK: - Scheduling

    /// Request the system to schedule a background app refresh.
    /// Safe to call on every app-to-background transition.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshService.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: BackgroundRefreshService.minimumFetchInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundRefreshService] Background refresh scheduled.")
        } catch let error as BGTaskScheduler.Error {
            switch error.code {
            case .notPermitted:
                print("[BackgroundRefreshService] Background refresh not permitted.")
            case .tooManyPendingTaskRequests:
                print("[BackgroundRefreshService] Refresh already scheduled — skipping.")
            case .unavailable:
                print("[BackgroundRefreshService] Background refresh unavailable (simulator or restricted).")
            case .immediateRunIneligible:
                print("[BackgroundRefreshService] Not eligible for an immediate run — waiting for the system.")
            @unknown default:
                print("[BackgroundRefreshService] Scheduling error: \(error.localizedDescription)")
            }
        } catch {
            print("[BackgroundRefreshService] Scheduling error: \(error.localizedDescription)")
        }
    }

    // MARK: - Task Handler

    private func handleAppRefresh(_ task: BGAppRefreshTask) async {
        // Always reschedule first — ensures continuity even if this task expires early.
        scheduleAppRefresh()

        let workTask = Task {
            await catchUp(viewing: nil)
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        await workTask.value
        task.setTaskCompleted(success: !workTask.isCancelled)
    }

    // MARK: - Catch-up

    /// Posts what every saved 2.x server finished or asked while nobody watched. Builds
    /// its own clients, so it also works after iOS launched the app in the background.
    func catchUp(viewing: String?) async {
        for server in ServerStore.shared.load() where server.apiVersion == .v2 {
            guard !Task.isCancelled else { return }
            do {
                let alerts = try await NotificationCatchUp.fetch(
                    client: server.makeAPIClient(), server: server.id, viewing: viewing, ledger: NotificationLedger()
                )
                await LocalNotificationService.shared.post(alerts, server: server.id)
            } catch {
                print("[BackgroundRefreshService] Catch-up failed for \(server.name): \(error.localizedDescription)")
            }
        }
    }
}
