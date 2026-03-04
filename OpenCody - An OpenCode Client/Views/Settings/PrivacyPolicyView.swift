//
//  PrivacyPolicyView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Displays a minimal privacy policy.
struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {

                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {

                            // Header
                            Label("Privacy Policy", systemImage: "hand.raised")
                                .font(Theme.Fonts.captionBold)
                                .foregroundStyle(Theme.Colors.silver)

                            Text("Last updated: March 2026")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.smoke)

                            // Section 1
                            policySection(
                                title: "Overview",
                                body: "OpenCody is an iOS client that connects to self-hosted OpenCode servers. The app itself does not collect, store, or transmit any personal data to third-party servers or services operated by us."
                            )

                            // Section 2
                            policySection(
                                title: "Data Processing",
                                body: "All communication occurs directly between your device and the OpenCode server you configure. The app does not act as an intermediary and does not route data through any external infrastructure. Server connection details (host, port) are stored locally on your device."
                            )

                            // Section 3
                            policySection(
                                title: "Local Storage",
                                body: "The app stores server connection settings and API keys locally on your device using the iOS Keychain and UserDefaults. This data never leaves your device except when communicating directly with your configured OpenCode server."
                            )

                            // Section 4
                            policySection(
                                title: "Analytics & Tracking",
                                body: "This app does not use any analytics, tracking, or crash reporting services. No usage data is collected."
                            )

                            // Section 5
                            policySection(
                                title: "Third-Party Services",
                                body: "The app does not integrate any third-party SDKs, advertising networks, or analytics frameworks. The only network communication is with the OpenCode server you configure yourself."
                            )

                            // Section 6
                            policySection(
                                title: "Your Rights",
                                body: "Since no personal data is collected or processed by us, there is no personal data to access, correct, or delete. You can remove all locally stored data by deleting the app from your device."
                            )

                            // Section 7
                            policySection(
                                title: "Contact",
                                body: "If you have questions about this privacy policy, please contact us via willsoftwaresolutions.de."
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Fonts.bodyBold)
                .foregroundStyle(Theme.Colors.cloud)
            Text(body)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
        }
    }
}
