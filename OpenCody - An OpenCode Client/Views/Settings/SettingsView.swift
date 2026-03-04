//
//  SettingsView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI
import SwiftUI

/// Root settings screen shown in the Settings tab.
/// Sections: Servers, Providers, MCP Servers, Server Config, About.
struct SettingsView: View {
    let connectionManager: ConnectionManager

    @EnvironmentObject private var serverStore: ServerStoreModel

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {

                    // MARK: - Connection
                    SettingsSection(title: "Connection") {
                        NavigationLink {
                            ServerListView(connectionManager: connectionManager)
                        } label: {
                            SettingsRow(
                                icon: "server.rack",
                                iconColor: Theme.Colors.cyberBlue,
                                title: "Servers",
                                detail: serverDetail
                            )
                        }
                    }

                    // MARK: - AI
                    SettingsSection(title: "AI") {
                        NavigationLink {
                            if let apiClient = connectionManager.activeAPIClient {
                                ProvidersView(apiClient: apiClient)
                            } else {
                                noConnectionView(for: "Providers")
                            }
                        } label: {
                            SettingsRow(
                                icon: "cpu",
                                iconColor: Theme.Colors.neonGreen,
                                title: "Providers",
                                detail: "API keys & models"
                            )
                        }

                        SettingsDivider()

                        NavigationLink {
                            if let apiClient = connectionManager.activeAPIClient {
                                MCPView(apiClient: apiClient)
                            } else {
                                noConnectionView(for: "MCP Servers")
                            }
                        } label: {
                            SettingsRow(
                                icon: "puzzlepiece.extension",
                                iconColor: Theme.Colors.electricPurple,
                                title: "MCP Servers",
                                detail: "Model Context Protocol"
                            )
                        }
                    }

                    // MARK: - Server
                    SettingsSection(title: "Server") {
                        NavigationLink {
                            if let apiClient = connectionManager.activeAPIClient {
                                ServerConfigView(apiClient: apiClient)
                            } else {
                                noConnectionView(for: "Server Config")
                            }
                        } label: {
                            SettingsRow(
                                icon: "gearshape.2",
                                iconColor: Theme.Colors.neonOrange,
                                title: "Server Config",
                                detail: "Models, agents, behaviour"
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

                        NavigationLink {
                            LicensesView()
                        } label: {
                            SettingsRow(
                                icon: "doc.text",
                                iconColor: Theme.Colors.cyberBlue,
                                title: "Licenses & Open Source",
                                detail: nil
                            )
                        }

                        SettingsDivider()

                        Link(destination: URL(string: "https://willsoftwaresolutions.de/impressum")!) {
                            SettingsRow(
                                icon: "building.2",
                                iconColor: Theme.Colors.neonOrange,
                                title: "Will Software Solutions",
                                detail: "Impressum"
                            )
                        }

                        SettingsDivider()

                        NavigationLink {
                            PrivacyPolicyView()
                        } label: {
                            SettingsRow(
                                icon: "hand.raised",
                                iconColor: Theme.Colors.electricPurple,
                                title: "Privacy",
                                detail: nil
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
                    }

                    // MARK: - Copyright
                    Text("© 2026 Will Software Solutions. All rights reserved.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Spacing.sm)
                }
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                connectionStatusBadge
            }
        }
    }

    // MARK: - Helpers

    private var serverDetail: String {
        let count = serverStore.servers.count
        if count == 0 { return "No servers" }
        return count == 1 ? "1 server" : "\(count) servers"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        if connectionManager.activeAPIClient != nil {
            StatusBadge(status: .active)
        } else {
            StatusBadge(status: .idle)
        }
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
