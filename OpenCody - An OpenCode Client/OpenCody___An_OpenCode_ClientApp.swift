//
//  OpenCody___An_OpenCode_ClientApp.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

@main
struct OpenCody___An_OpenCode_ClientApp: App {
    init() {
        BackgroundRefreshService.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
