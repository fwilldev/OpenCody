//
//  SettingsView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Root settings screen shown in the Settings tab.
/// Sections: Servers, Providers, MCP Servers, Server Config, About.
struct SettingsView: View {
    let connectionManager: ConnectionManager

    @EnvironmentObject private var serverStore: ServerStoreModel
    @Bindable private var notificationSettings = NotificationSettings.shared
    @AppStorage("appearancePreference") private var appearancePreference: String = AppearancePreference.system.rawValue

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {

                    // MARK: - Connection
                    SettingsSection(title: "Connection") {
                        NavigationLink(value: AppRouter.SettingsRoute.servers) {
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
                        NavigationLink(value: AppRouter.SettingsRoute.providers) {
                            SettingsRow(
                                icon: "cpu",
                                iconColor: Theme.Colors.neonGreen,
                                title: "Providers",
                                detail: "API keys & models"
                            )
                        }

                        SettingsDivider()

                        NavigationLink(value: AppRouter.SettingsRoute.mcp) {
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
                        Text(notificationsHint)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                            .padding(.bottom, Theme.Spacing.xs)

                        SettingsToggleRow(
                            icon: "checkmark.circle",
                            iconColor: Theme.Colors.neonGreen,
                            title: "Turn Complete",
                            detail: "When a session finishes",
                            isOn: $notificationSettings.turnCompleteEnabled
                        )

                        SettingsDivider()

                        SettingsToggleRow(
                            icon: "exclamationmark.triangle",
                            iconColor: Theme.Colors.neonOrange,
                            title: "Errors",
                            detail: "Session error alerts",
                            isOn: $notificationSettings.errorsEnabled
                        )

                        SettingsDivider()

                        SettingsToggleRow(
                            icon: "lock.shield",
                            iconColor: Theme.Colors.electricPurple,
                            title: "Permissions",
                            detail: "Tool approval requests",
                            isOn: $notificationSettings.permissionsEnabled
                        )

                        SettingsDivider()

                        SettingsToggleRow(
                            icon: "questionmark.bubble",
                            iconColor: Theme.Colors.cyberBlue,
                            title: "Questions",
                            detail: "Agent questions",
                            isOn: $notificationSettings.questionsEnabled
                        )
                    }

                    // MARK: - Support
                    SettingsSection(title: "Support") {
                        NavigationLink(value: AppRouter.SettingsRoute.tipJar) {
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

                        NavigationLink(value: AppRouter.SettingsRoute.licenses) {
                            SettingsRow(
                                icon: "doc.text",
                                iconColor: Theme.Colors.cyberBlue,
                                title: "Licenses & Open Source",
                                detail: nil
                            )
                        }

                        SettingsDivider()

                        NavigationLink(value: AppRouter.SettingsRoute.privacy) {
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
        .navigationDestination(for: AppRouter.SettingsRoute.self) { route in
            switch route {
            case .servers:
                ServerListView(connectionManager: connectionManager)
            case .providers:
                if let apiClient = connectionManager.activeAPIClient {
                    ProvidersView(apiClient: apiClient)
                } else {
                    noConnectionView(for: "Providers")
                }
            case .mcp:
                if let apiClient = connectionManager.activeAPIClient {
                    MCPView(apiClient: apiClient)
                } else {
                    noConnectionView(for: "MCP Servers")
                }
            case .tipJar: TipJarView()
            case .licenses: LicensesView()
            case .privacy: PrivacyPolicyView()
            }
        }
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Helpers

    /// Notifications only come from OpenCode 2.x servers.
    private var notificationsHint: String {
        let active = serverStore.servers.first { $0.id == connectionManager.activeServerID }
        if active?.apiVersion == .v1 {
            return "Notifications need OpenCode 2 or later. This server runs OpenCode 1.x."
        }
        return "Alerts arrive while OpenCody is open, and anything missed shows up when you return. For alerts while it's closed, turn on Push Notifications for your server under Servers."
    }

    private var serverDetail: String {
        let count = serverStore.servers.count
        if count == 0 { return "No servers" }
        return count == 1 ? "1 server" : "\(count) servers"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @ViewBuilder
    private func noConnectionView(for name: String) -> some View {
        EmptyStateView(
            systemImage: "wifi.slash",
            title: "Not Connected",
            message: "Connect to a server in the Servers section to access \(name)."
        )
        .background(Theme.Colors.deepBlack)
        .navigationTitle(name)
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

// MARK: - SettingsToggleRow

/// Toggle row matching the visual style of SettingsRow — icon, title, detail, toggle.
private struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        // The row is the toggle's label, so VoiceOver reads the title with the switch.
        Toggle(isOn: $isOn) {
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
            }
        }
        .tint(Theme.Colors.cyberBlue)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
