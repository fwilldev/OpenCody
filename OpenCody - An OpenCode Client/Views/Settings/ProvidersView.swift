//
//  ProvidersView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Lists all providers with their auth status and model count.
/// Tap a provider to see details and manage API key.
struct ProvidersView: View {
    let apiClient: APIClient

    @State private var response: ProviderAPI.ProviderListResponse? = nil
    @State private var isLoading = true
    @State private var error: String? = nil

    private var providerAPI: ProviderAPI { ProviderAPI(client: apiClient) }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading providers…")
                    .tint(Theme.Colors.cyberBlue)
                    .foregroundStyle(Theme.Colors.silver)
            } else if let err = error {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Error",
                    message: err,
                    action: { Task { await loadProviders() } },
                    actionLabel: "Retry"
                )
            } else if let resp = response {
                providerList(resp)
            }
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProviders() }
        .refreshable { await loadProviders() }
    }

    // MARK: - Provider List

    @ViewBuilder
    private func providerList(_ resp: ProviderAPI.ProviderListResponse) -> some View {
        let connected = Set(resp.connected)
        let sorted = resp.all.sorted { $0.name < $1.name }

        if sorted.isEmpty {
            EmptyStateView(
                systemImage: "cpu",
                title: "No Providers",
                message: "No providers are configured on this server."
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.Colors.graphite)
                                .frame(height: 1)
                                .padding(.leading, 52)
                                .padding(.vertical, 2)
                        }
                        NavigationLink {
                            ProviderDetailView(
                                provider: provider,
                                isConnected: connected.contains(provider.id),
                                apiClient: apiClient
                            )
                        } label: {
                            ProviderRowView(
                                provider: provider,
                                isConnected: connected.contains(provider.id)
                            )
                        }
                    }
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
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
            }
        }
    }

    // MARK: - Load

    private func loadProviders() async {
        isLoading = true
        error = nil
        do {
            response = try await providerAPI.list()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - ProviderRowView

private struct ProviderRowView: View {
    let provider: Provider
    let isConnected: Bool

    private var modelCount: Int { provider.models.count }
    private var statusText: String { isConnected ? "Connected" : "Not connected" }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Provider icon placeholder
            ZStack {
                Circle()
                    .fill(isConnected ? Theme.Colors.neonGreen.opacity(0.15) : Theme.Colors.smoke)
                    .frame(width: 40, height: 40)
                Text(String(provider.name.prefix(2)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(isConnected ? Theme.Colors.neonGreen : Theme.Colors.silver)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.cloud)
                HStack(spacing: Theme.Spacing.sm) {
                    Text(modelCount == 1 ? "1 model" : "\(modelCount) models")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                    Text("•")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                    Text(statusText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(isConnected ? Theme.Colors.neonGreen : Theme.Colors.silver)
                }
            }
            Spacer()
            StatusBadge(
                status: isConnected ? .active : .idle
            )
        }
        .padding(.vertical, 6)
    }
}
