//
//  ProvidersView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Lists providers with their auth status, split into connected and available.
///
/// Providers the server exposes an auth method for can be connected from here.
/// Providers without one are configured through environment variables or the config
/// file; their rows say so instead of offering a button that does nothing.
struct ProvidersView: View {
    let apiClient: APIClient

    @State private var model: ProvidersViewModel
    @State private var authTarget: ProviderEntry? = nil

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        _model = State(initialValue: ProvidersViewModel(apiClient: apiClient))
    }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            if model.isLoading && model.entries.isEmpty {
                loadingSkeleton
            } else if let err = model.loadError, model.entries.isEmpty {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Could Not Load",
                    message: err,
                    action: { Task { await model.load() } },
                    actionLabel: "Retry"
                )
            } else if model.entries.isEmpty {
                EmptyStateView(
                    systemImage: "cpu",
                    title: "No Providers",
                    message: "No providers are configured on this server."
                )
            } else {
                content
            }
        }
        .overlay(alignment: .top) { bannerOverlay }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: "Search providers and models")
        .sheet(item: $authTarget) { entry in
            ProviderAuthSheet(entry: entry, model: model)
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if !model.connected.isEmpty {
                    section(title: "Connected", entries: model.connected)
                }
                if !model.available.isEmpty {
                    section(title: "Available", entries: model.available)
                }
                if model.connected.isEmpty && model.available.isEmpty {
                    Text("Nothing matches \"\(model.searchText)\".")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.silver)
                        .padding(.top, Theme.Spacing.xl)
                }
            }
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private func section(title: String, entries: [ProviderEntry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.smoke)
                    .kerning(0.8)
                Spacer()
                Text("\(entries.count)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.smoke)
            }
            .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.Colors.graphite)
                            .frame(height: 1)
                            .padding(.leading, 52)
                            .padding(.vertical, 2)
                    }
                    NavigationLink {
                        ProviderDetailView(
                            providerID: entry.id,
                            model: model,
                            onConnect: { authTarget = entry }
                        )
                    } label: {
                        ProviderRowView(
                            entry: entry,
                            isPending: model.pending.contains(entry.id)
                        )
                    }
                    .contextMenu {
                        if entry.isConnected {
                            Button(role: .destructive) {
                                Task { await model.disconnect(providerID: entry.id) }
                            } label: {
                                Label("Disconnect", systemImage: "key.slash")
                            }
                        } else {
                            Button {
                                authTarget = entry
                            } label: {
                                Label("Connect", systemImage: "key")
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.carbon))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.graphite, lineWidth: 1))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }

    @ViewBuilder
    private var bannerOverlay: some View {
        if let banner = model.banner {
            ErrorBanner(error: .validation(0, banner), onDismiss: { model.banner = nil })
                // `ErrorBanner` animates in from `onAppear`, so a replacement message
                // needs a fresh identity to animate rather than swap silently.
                .id(banner)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Loading

    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Theme.Colors.graphite).frame(height: 1).padding(.leading, 52)
                }
                HStack(spacing: Theme.Spacing.md) {
                    Circle().fill(Theme.Colors.fillMuted).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 110, height: 13)
                        SkeletonBlock(width: 160, height: 10)
                    }
                    Spacer()
                    SkeletonBlock(width: 58, height: 20, cornerRadius: 10)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.carbon))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.graphite, lineWidth: 1))
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, Theme.Spacing.sm)
    }
}

// MARK: - ProviderRowView

private struct ProviderRowView: View {
    let entry: ProviderEntry
    let isPending: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(entry.isConnected ? Theme.Colors.neonGreen.opacity(0.15) : Theme.Colors.fillMuted)
                    .frame(width: 40, height: 40)
                Text(String(entry.name.prefix(2)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.isConnected ? Theme.Colors.neonGreen : Theme.Colors.silver)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.cloud)
                HStack(spacing: 6) {
                    Text(entry.modelCount == 1 ? "1 model" : "\(entry.modelCount) models")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                    Text("•")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                    Text(statusText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()

            if isPending {
                ProgressView().scaleEffect(0.7).tint(Theme.Colors.cyberBlue)
            } else {
                // Dot only: `ConnectionStatus` labels are session wording ("Done",
                // "Idle") and read as nonsense next to a provider.
                StatusBadge(status: entry.isConnected ? .active : .idle, showLabel: false)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusText: String {
        entry.isConnected ? "Connected" : "Tap to connect"
    }

    private var statusColor: Color {
        entry.isConnected ? Theme.Colors.neonGreen : Theme.Colors.cyberBlue
    }
}
