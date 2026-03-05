//
//  ProviderDetailView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Shows provider details: model list.
struct ProviderDetailView: View {
    let provider: Provider
    let isConnected: Bool

    @Environment(\.dismiss) private var dismiss
    private var sortedModels: [Model] { provider.models.values.sorted { $0.name < $1.name } }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header
                    providerHeader

                    // Content
                    if isConnected {
                        modelsSection
                    } else {
                        notConnectedSection
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var providerHeader: some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(isConnected ? Theme.Colors.neonGreen.opacity(0.15) : Theme.Colors.smoke)
                        .frame(width: 56, height: 56)
                    Text(String(provider.name.prefix(2)).uppercased())
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(isConnected ? Theme.Colors.neonGreen : Theme.Colors.silver)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.Colors.cloud)
                    Text("\(sortedModels.count) models available")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
                Spacer()
                StatusBadge(
                    status: isConnected ? .active : .idle
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Available Models", count: sortedModels.count)
                    .padding(.bottom, Theme.Spacing.sm)

                if sortedModels.isEmpty {
                    Text("No models available")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                        .padding(.vertical, Theme.Spacing.sm)
                } else {
                    ForEach(Array(sortedModels.enumerated()), id: \.element.id) { index, model in
                        if index > 0 {
                            Divider().background(Theme.Colors.slate)
                        }
                        ModelRowView(model: model)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Not Connected Section

    private var notConnectedSection: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "server.rack")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.Colors.silver)

                Text("Manage your Providers on your Server")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.silver)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(Theme.Fonts.captionBold)
                .foregroundStyle(Theme.Colors.silver)
            Spacer()
            Text("\(count)")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Theme.Colors.slate)
                )
        }
    }

}

// MARK: - ModelRowView

private struct ModelRowView: View {
    let model: Model

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.cloud)
                Text(model.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.silver)
            }
            Spacer()
            capabilityBadges
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var capabilityBadges: some View {
        HStack(spacing: 4) {
            if model.capabilities.reasoning {
                capBadge("R", color: Theme.Colors.electricPurple)
            }
            if model.capabilities.attachment {
                capBadge("V", color: Theme.Colors.cyberBlue)
            }
            if model.capabilities.toolcall {
                capBadge("T", color: Theme.Colors.neonGreen)
            }
        }
    }

    private func capBadge(_ letter: String, color: Color) -> some View {
        Text(letter)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.15))
            )
    }
}
