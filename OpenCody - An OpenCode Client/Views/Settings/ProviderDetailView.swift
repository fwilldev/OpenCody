//
//  ProviderDetailView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Provider details: connection state, credential actions, and the model catalogue
/// with pricing, limits and capabilities.
///
/// Reads its entry from the view model by ID rather than taking a snapshot, so
/// connecting or disconnecting updates this screen without popping back.
struct ProviderDetailView: View {
    let providerID: String
    let model: ProvidersViewModel
    /// Opens the auth sheet, which the list view owns.
    let onConnect: () -> Void

    @State private var modelSearch = ""
    @State private var showsDisconnectConfirm = false

    private var entry: ProviderEntry? { model.entry(id: providerID) }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            if let entry {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        header(entry)
                        connectionSection(entry)
                        modelsSection(entry)
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
            } else {
                // The provider vanished — the list reloaded and no longer has it.
                EmptyStateView(
                    systemImage: "cpu",
                    title: "Provider Unavailable",
                    message: "This provider is no longer reported by the server."
                )
            }
        }
        .navigationTitle(entry?.name ?? providerID)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove stored credentials?",
            isPresented: $showsDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await model.disconnect(providerID: providerID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sessions using this provider's models will stop working until it is connected again.")
        }
    }

    // MARK: - Header

    private func header(_ entry: ProviderEntry) -> some View {
        GlassCard {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(entry.isConnected ? Theme.Colors.neonGreen.opacity(0.15) : Theme.Colors.fillMuted)
                        .frame(width: 56, height: 56)
                    Text(String(entry.name.prefix(2)).uppercased())
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(entry.isConnected ? Theme.Colors.neonGreen : Theme.Colors.silver)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.Colors.cloud)
                    Text(entry.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.silver)
                    Text("\(entry.modelCount) models · \(entry.sourceLabel)")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
                Spacer()
                // Dot only — `ConnectionStatus`'s labels are session wording ("Done",
                // "Idle") and mean nothing for a provider.
                StatusBadge(status: entry.isConnected ? .active : .idle, showLabel: false)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Connection

    private func connectionSection(_ entry: ProviderEntry) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionTitle("Connection")

                if entry.isConnected {
                    row(
                        icon: "checkmark.seal",
                        color: Theme.Colors.neonGreen,
                        title: "Credentials stored",
                        detail: "This provider's models are available to the agent."
                    )
                    Button {
                        showsDisconnectConfirm = true
                    } label: {
                        HStack {
                            if model.pending.contains(entry.id) {
                                ProgressView().scaleEffect(0.7).tint(Theme.Colors.onDestructiveAccent)
                            }
                            Text("Disconnect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .destructiveButton()
                    .disabled(model.pending.contains(entry.id))
                } else if entry.supportsApiKey {
                    row(
                        icon: "key",
                        color: Theme.Colors.cyberBlue,
                        title: "Connect with an API key",
                        detail: entry.envVarHint.map { "Or set \($0) in the server's environment." }
                            ?? "Add a key to use this provider's models."
                    )
                    Button {
                        onConnect()
                    } label: {
                        Text("Connect").frame(maxWidth: .infinity)
                    }
                    .primaryButton()
                } else {
                    // OAuth-only provider: see ProviderAuthSheet for why the app does
                    // not drive those flows.
                    row(
                        icon: "person.badge.key",
                        color: Theme.Colors.neonOrange,
                        title: "Needs a browser sign-in",
                        detail: "This provider doesn't accept a plain API key. Run opencode auth login on the server."
                    )
                    Button {
                        onConnect()
                    } label: {
                        Text("How to Connect").frame(maxWidth: .infinity)
                    }
                    .secondaryButton()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Models

    private func modelsSection(_ entry: ProviderEntry) -> some View {
        let models = filteredModels(entry)
        return GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionTitle("Models", count: models.count)

                if entry.modelCount > 8 {
                    GlassTextField(
                        placeholder: "Filter models",
                        text: $modelSearch,
                        autocapitalization: .never
                    )
                }

                if models.isEmpty {
                    Text(modelSearch.isEmpty ? "No models available" : "No model matches \"\(modelSearch)\".")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                        .padding(.vertical, Theme.Spacing.sm)
                } else {
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().background(Theme.Colors.slate)
                        }
                        ModelRowView(
                            model: item,
                            isDefault: item.id == entry.defaultModelID
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func filteredModels(_ entry: ProviderEntry) -> [Model] {
        let all = entry.provider.models.values
        let query = modelSearch.trimmingCharacters(in: .whitespaces)
        let matched = query.isEmpty
            ? Array(all)
            : all.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
            }
        return matched.sorted { lhs, rhs in
            // The default model first, then newest release, then name — so the model
            // someone is most likely looking for is at the top.
            if (lhs.id == entry.defaultModelID) != (rhs.id == entry.defaultModelID) {
                return lhs.id == entry.defaultModelID
            }
            let lhsDate = lhs.releaseDate ?? ""
            let rhsDate = rhs.releaseDate ?? ""
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Small Views

    private func sectionTitle(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title)
                .font(Theme.Fonts.captionBold)
                .foregroundStyle(Theme.Colors.silver)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.silver)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.Colors.slate))
            }
        }
    }

    private func row(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.cloud)
                Text(detail)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.silver)
            }
            Spacer()
        }
    }
}

// MARK: - ModelRowView

private struct ModelRowView: View {
    let model: Model
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.cloud)
                        if isDefault {
                            tag("DEFAULT", color: Theme.Colors.cyberBlue)
                        }
                        if let statusTag {
                            tag(statusTag.0, color: statusTag.1)
                        }
                    }
                    Text(model.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.silver)
                }
                Spacer()
                capabilityBadges
            }

            HStack(spacing: Theme.Spacing.sm) {
                metric(limitText)
                metric(costText)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Facts

    /// Context and output budget, the numbers that decide whether a model fits a task.
    private var limitText: String {
        "\(compactTokens(model.limit.context)) ctx · \(compactTokens(model.limit.output)) out"
    }

    /// Price per million tokens.
    ///
    /// The API already reports cost in USD per million tokens — Claude Sonnet comes
    /// back as `cost.input == 3`, meaning $3/Mtok — so the numbers are used as given.
    private var costText: String {
        let input = model.cost.input
        let output = model.cost.output
        if input == 0 && output == 0 { return "Free" }
        return "$\(price(input)) in · $\(price(output)) out /Mtok"
    }

    /// Up to two decimals, trailing zeros dropped: `3`, `0.25`, `1.5`.
    private func price(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        return String(format: "%g", rounded)
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return millions == millions.rounded()
                ? "\(Int(millions))M"
                : String(format: "%.1fM", millions)
        }
        if value >= 1_000 { return "\(value / 1_000)K" }
        return "\(value)"
    }

    private var statusTag: (String, Color)? {
        switch model.status {
        case .active: return nil
        case .alpha: return ("ALPHA", Theme.Colors.neonOrange)
        case .beta: return ("BETA", Theme.Colors.electricPurple)
        case .deprecated: return ("DEPRECATED", Theme.Colors.hotPink)
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private var capabilityBadges: some View {
        HStack(spacing: 4) {
            if model.capabilities.reasoning {
                capBadge("R", color: Theme.Colors.electricPurple, help: "Reasoning")
            }
            if model.capabilities.attachment {
                capBadge("V", color: Theme.Colors.cyberBlue, help: "Vision / attachments")
            }
            if model.capabilities.toolcall {
                capBadge("T", color: Theme.Colors.neonGreen, help: "Tool calls")
            }
        }
    }

    private func capBadge(_ letter: String, color: Color, help: String) -> some View {
        Text(letter)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.15)))
            .accessibilityLabel(help)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)))
    }

    private func metric(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.Colors.silver)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.Colors.fillSubtle))
    }
}
