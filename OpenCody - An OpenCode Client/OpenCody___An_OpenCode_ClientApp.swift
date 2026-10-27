//
//  OpenCody___An_OpenCode_ClientApp.swift
//  OpenCody - An OpenCode Client
//

import BackgroundTasks
import SwiftUI

@main
struct OpenCody___An_OpenCode_ClientApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate

    init() {
        NotificationDelegate.shared.install()
        // Up to 1.9 a background refresh posted local alerts; 1.10 relies on push alone.
        BGTaskScheduler.shared.cancelAllTaskRequests()
        for key in ["turnComplete", "errors", "permissions", "questions", "ledger", "ledger.baselines"] {
            UserDefaults.standard.removeObject(forKey: "notification.\(key)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
