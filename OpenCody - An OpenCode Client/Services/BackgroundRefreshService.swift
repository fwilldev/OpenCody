//
//  BackgroundRefreshService.swift
//  OpenCody - An OpenCode Client
//

import BackgroundTasks
import Foundation
import UserNotifications

/// Manages BGAppRefreshTask registration and handling.
///
/// On a background refresh the service polls the active server's session list
/// and fires a local notification if any sessions are still running (busy), prompting
/// the user to return to the app — where the SSE stream will surface any pending
/// permission requests or completed results.
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

    // MARK: - APIClient Provider

    /// Closure set by the App entry point to provide the currently active APIClient.
    /// Avoids a direct dependency on ConnectionManager.
    var apiClientProvider: (() -> APIClient?)?

    private var activeAPIClient: APIClient? { apiClientProvider?() }

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
            await performRefresh()
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        await workTask.value
        task.setTaskCompleted(success: !workTask.isCancelled)
    }

    // MARK: - Refresh Logic

    /// Poll the active server for running sessions; notify the user to check on activity.
    private func performRefresh() async {
        guard let apiClient = activeAPIClient else {
            print("[BackgroundRefreshService] No active API client - skipping refresh.")
            return
        }

        do {
            let sessionAPI = SessionAPI(client: apiClient)
            let sessions = try await sessionAPI.list()
            let statusMap = try await sessionAPI.status()

            let busySessions = sessions.filter { session in
                if case .busy = statusMap[session.id] { return true }
                return false
            }

            if !busySessions.isEmpty {
                let content = UNMutableNotificationContent()
                content.title = "OpenCody"
                content.body = busySessions.count == 1
                    ? "1 session is still running. Tap to check."
                    : "\(busySessions.count) sessions are still running. Tap to check."
                content.sound = .default

                let notifRequest = UNNotificationRequest(
                    identifier: "bg-refresh-\(Int(Date().timeIntervalSince1970))",
                    content: content,
                    trigger: nil
                )
                try? await UNUserNotificationCenter.current().add(notifRequest)
            }

            print("[BackgroundRefreshService] Refresh complete. Busy sessions: \(busySessions.count)")
        } catch {
            print("[BackgroundRefreshService] Refresh error: \(error.localizedDescription)")
        }
    }
}
