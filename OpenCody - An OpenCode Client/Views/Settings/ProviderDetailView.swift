//
//  ProviderDetailView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Shows provider details: model list + API key management.
struct ProviderDetailView: View {
    let provider: Provider
    let isConnected: Bool
    let apiClient: APIClient

    @Environment(\.dismiss) private var dismiss
    @State private var authMethods: [ProviderAuthMethod] = []
    @State private var isLoadingMethods = true
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var saveSuccess = false
    @State private var selectedTab = 0

    private var providerAPI: ProviderAPI { ProviderAPI(client: apiClient) }
    private var sortedModels: [Model] { provider.models.values.sorted { $0.name < $1.name } }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header
                    providerHeader

                    // Tab picker
                    Picker("", selection: $selectedTab) {
                        Text("Models").tag(0)
                        Text("Authentication").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.md)

                    // Content
                    if selectedTab == 0 {
                        modelsSection
                    } else {
                        authSection
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAuthMethods() }
        .overlay(
            saveSuccessBanner,
            alignment: .top
        )
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

    // MARK: - Auth Section

    @ViewBuilder
    private var authSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if isLoadingMethods {
                GlassCard {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(Theme.Colors.cyberBlue)
                        Spacer()
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            } else if authMethods.isEmpty {
                GlassCard {
                    Text("No authentication methods available for this provider.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.silver)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Spacing.md)
            } else {
                ForEach(authMethods, id: \.type) { method in
                    if method.type == .api {
                        apiKeySection(method: method)
                    }
                }
            }

            // Environment variables hint
            if !provider.env.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Label("Environment Variables", systemImage: "terminal")
                            .font(Theme.Fonts.captionBold)
                            .foregroundStyle(Theme.Colors.silver)
                        ForEach(provider.env, id: \.self) { envVar in
                            Text(envVar)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.Colors.neonGreen)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Theme.Colors.neonGreen.opacity(0.08))
                                )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }

    private func apiKeySection(method: ProviderAuthMethod) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Label(method.label, systemImage: "key")
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.cloud)

                GlassTextField(
                    placeholder: "Enter API key",
                    text: $apiKey,
                    isSecure: true
                )

                if let err = saveError {
                    Text(err)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.hotPink)
                }

                Button {
                    Task { await saveApiKey(method: method) }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Text("Save API Key")
                        }
                        Spacer()
                    }
                }
                .primaryButton()
                .disabled(apiKey.isEmpty || isSaving)
                .opacity(apiKey.isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Save Banner

    @ViewBuilder
    private var saveSuccessBanner: some View {
        if saveSuccess {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.neonGreen)
                Text("API key saved successfully")
                    .font(Theme.Fonts.captionBold)
                    .foregroundStyle(Theme.Colors.cloud)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(Theme.Colors.neonGreen.opacity(0.15))
                    .overlay(Capsule().stroke(Theme.Colors.neonGreen.opacity(0.3), lineWidth: 1))
            )
            .padding(.top, Theme.Spacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
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

    private func loadAuthMethods() async {
        isLoadingMethods = true
        do {
            authMethods = try await providerAPI.authMethods(providerID: provider.id)
        } catch {
            // Silently fail — just show no methods
            authMethods = []
        }
        isLoadingMethods = false
    }

    private func saveApiKey(method: ProviderAuthMethod) async {
        isSaving = true
        saveError = nil
        do {
            try await providerAPI.authenticateWithApiKey(
                providerID: provider.id,
                method: method.type.rawValue,
                apiKey: apiKey
            )
            apiKey = ""
            withAnimation {
                saveSuccess = true
            }
            // Auto-dismiss the success banner after 2s
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                saveSuccess = false
            }
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
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
