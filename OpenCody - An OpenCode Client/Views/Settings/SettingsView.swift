//
//  SettingsView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI
import UserNotifications

/// Root settings screen shown in the Settings tab.
/// Sections: Servers, Providers, MCP Servers, Server Config, About.
struct SettingsView: View {
    let connectionManager: ConnectionManager

    @EnvironmentObject private var serverStore: ServerStoreModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// `nil` until read; re-read on return from the Settings app.
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var showPrivacy = false
    @AppStorage("appearancePreference") private var appearancePreference: String = AppearancePreference.system.rawValue

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {

                    // MARK: - Connection
                    SettingsSection(title: "Connection") {
                        NavigationLink(value: AppRouter.Route.settings(.servers)) {
                            SettingsRow(
                                icon: "server.rack",
                                iconColor: Theme.Colors.cyberBlue,
                                title: "Servers",
                                detail: serverDetail
                            )
                        }
                    }

                    // MARK: - Appearance
                    SettingsSection(title: "Appearance") {
                        SettingsRow(
                            icon: "circle.lefthalf.filled",
                            iconColor: Theme.Colors.cyberBlue,
                            title: "Theme",
                            detail: "Follow the system or pick a fixed look",
                            showChevron: false
                        )

                        Picker("Theme", selection: $appearancePreference) {
                            ForEach(AppearancePreference.allCases) { preference in
                                Text(preference.label).tag(preference.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(.top, Theme.Spacing.sm)
                    }

                    // MARK: - AI
                    SettingsSection(title: "AI") {
                        NavigationLink(value: AppRouter.Route.settings(.providers)) {
                            SettingsRow(
                                icon: "cpu",
                                iconColor: Theme.Colors.neonGreen,
                                title: "Providers",
                                detail: "API keys & models"
                            )
                        }

                        SettingsDivider()

                        NavigationLink(value: AppRouter.Route.settings(.mcp)) {
                            SettingsRow(
                                icon: "puzzlepiece.extension",
                                iconColor: Theme.Colors.electricPurple,
                                title: "MCP Servers",
                                detail: "Model Context Protocol"
                            )
                        }
                    }

                    // MARK: - Notifications
                    SettingsSection(title: "Notifications") {
                        Text("Notifications need OpenCode 2 and the opencody-notify plugin on the server. Pair each server below.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, Theme.Spacing.xs)

                        HStack {
                            SettingsRow(
                                icon: notificationsAllowed ? "bell.fill" : "bell.slash",
                                iconColor: notificationsAllowed ? Theme.Colors.neonGreen : Theme.Colors.neonOrange,
                                title: "Allow Notifications",
                                detail: permissionDetail,
                                showChevron: false
                            )
                            if notificationStatus == .notDetermined {
                                Button("Allow") { Task { await requestNotifications() } }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.Colors.cyberBlue)
                            } else if notificationStatus == .denied {
                                Button("Settings") {
                                    openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                                }
                                .buttonStyle(.bordered)
                                .tint(Theme.Colors.cyberBlue)
                            }
                        }

                        ForEach(serverStore.servers) { server in
                            let status = PushStatus(apiVersion: server.apiVersion, pairing: PushService.shared.pairing(for: server.id))
                            SettingsDivider()
                            NavigationLink(value: AppRouter.Route.settings(.push(server.id))) {
                                SettingsRow(
                                    icon: status == .paired ? "bell.badge" : "server.rack",
                                    iconColor: color(for: status),
                                    title: server.name,
                                    detail: status.label
                                )
                            }
                        }
                    }
                    .task(id: scenePhase) {
                        guard scenePhase == .active else { return }
                        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                    }

                    // MARK: - Support
                    SettingsSection(title: "Support") {
                        NavigationLink(value: AppRouter.Route.settings(.tipJar)) {
                            SettingsRow(
                                icon: "heart.fill",
                                iconColor: Theme.Colors.hotPink,
                                title: "Tip Jar",
                                detail: "Support OpenCody's development"
                            )
                        }
                    }

                    // MARK: - About
                    SettingsSection(title: "About") {
                        HStack {
                            SettingsRow(
                                icon: "info.circle",
                                iconColor: Theme.Colors.silver,
                                title: "OpenCody",
                                detail: nil,
                                showChevron: false
                            )
                            Spacer()
                            Text(appVersion)
                                .font(Theme.Fonts.codeCaption)
                                .foregroundStyle(Theme.Colors.smoke)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Theme.Colors.slate.opacity(0.5))
                                )
                        }

                        SettingsDivider()

                        NavigationLink(value: AppRouter.Route.settings(.licenses)) {
                            SettingsRow(
                                icon: "doc.text",
                                iconColor: Theme.Colors.cyberBlue,
                                title: "Licenses & Open Source",
                                detail: nil
                            )
                        }

                        SettingsDivider()

                        Button { showPrivacy = true } label: {
                            SettingsRow(
                                icon: "hand.raised",
                                iconColor: Theme.Colors.electricPurple,
                                title: "Privacy",
                                detail: nil
                            )
                        }

                        SettingsDivider()

                        Link(destination: AppLinks.sourceCode) {
                            SettingsRow(
                                icon: "chevron.left.forwardslash.chevron.right",
                                iconColor: Theme.Colors.neonGreen,
                                title: "OpenCody on GitHub",
                                detail: "Source code, issues and contributions"
                            )
                        }

                        SettingsDivider()

                        Link(destination: URL(string: "https://github.com/sst/opencode")!) {
                            SettingsRow(
                                icon: "link",
                                iconColor: Theme.Colors.cyberBlue,
                                title: "OpenCode on GitHub",
                                detail: nil
                            )
                        }

                        SettingsDivider()

                        Link(destination: URL(string: "https://willsoftwaresolutions.de")!) {
                            SettingsRow(
                                icon: "building.2",
                                iconColor: Theme.Colors.neonOrange,
                                title: "About the Developer",
                                detail: "Will Software Solutions"
                            )
                        }
                    }

                }
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showPrivacy) {
            SafariView(url: AppLinks.privacyPolicy)
                .ignoresSafeArea()
        }
    }

    // MARK: - Helpers

    private var notificationsAllowed: Bool {
        [.authorized, .provisional, .ephemeral].contains(notificationStatus)
    }

    private var permissionDetail: String {
        switch notificationStatus {
        case .notDetermined: "Not asked yet"
        case .denied: "Off. Turn them on in the Settings app."
        case nil: " "
        default: "On"
        }
    }

    private func color(for status: PushStatus) -> Color {
        switch status {
        case .paired: Theme.Colors.neonGreen
        case .broken: Theme.Colors.neonOrange
        case .off, .unsupported: Theme.Colors.smoke
        }
    }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var serverDetail: String {
        let count = serverStore.servers.count
        if count == 0 { return "No servers" }
        return count == 1 ? "1 server" : "\(count) servers"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - SettingsSection

/// A grouped section with a header label and glass card container.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Theme.Colors.smoke)
                .kerning(0.8)
                .padding(.leading, Theme.Spacing.xs)

            VStack(spacing: 0) {
                content
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.carbon)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.Colors.graphite, lineWidth: 1)
            )
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - SettingsDivider

/// Subtle divider between rows inside a settings section.
private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.graphite)
            .frame(height: 1)
            .padding(.leading, 52)
            .padding(.vertical, 2)
    }
}

// MARK: - SettingsRow

/// Reusable row for a settings list item.
private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String?
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.cloud)
                if let detail {
                    Text(detail)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
            }

            Spacer()

            // Chevron
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.smoke)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
