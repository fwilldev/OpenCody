//
//  ContentView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 24.02.26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("appearancePreference") private var appearancePreference: String = AppearancePreference.system.rawValue

    var body: some View {
        RootView()
            .preferredColorScheme(AppearancePreference(rawValue: appearancePreference)?.colorScheme)
    }
}
