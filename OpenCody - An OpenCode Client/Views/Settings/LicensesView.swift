//
//  LicensesView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Displays open-source license information and attributions.
struct LicensesView: View {
    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {

                    // MARK: - OpenCode Attribution
                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Label("OpenCode", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(Theme.Fonts.captionBold)
                                .foregroundStyle(Theme.Colors.silver)

                            Text("This app uses \"OpenCode – The open source coding agent\" (Copyright © Anomaly Innovations and contributors), licensed under the MIT License.")
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.Colors.cloud)

                            Text("This app is an unofficial iOS client for OpenCode servers. It is not affiliated with or endorsed by Anomaly Innovations or opencode.ai.")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.silver)

                            Divider()
                                .background(Theme.Colors.slate)

                            Link(destination: URL(string: "https://github.com/sst/opencode/blob/dev/LICENSE")!) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.cyberBlue)
                                    Text("View MIT License on GitHub")
                                        .font(Theme.Fonts.body)
                                        .foregroundStyle(Theme.Colors.cyberBlue)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.smoke)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .navigationTitle("Licenses & Open Source")
        .navigationBarTitleDisplayMode(.inline)
    }
}
