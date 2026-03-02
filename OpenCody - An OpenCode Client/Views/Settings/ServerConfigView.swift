//
//  ServerConfigView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Loads and edits the remote server's config.
/// Shows the most commonly useful fields; advanced fields shown in expandable section.
struct ServerConfigView: View {
    let apiClient: APIClient

    @State private var config: ServerConfig? = nil
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String? = nil
    @State private var saveError: String? = nil
    @State private var saveSuccess = false
    @State private var showAdvanced = false

    // Editable state — basic fields
    @State private var model = ""
    @State private var smallModel = ""
    @State private var username = ""
    @State private var logLevel = ""
    @State private var snapshot = false
    @State private var autoshare = false

    private var configAPI: ConfigAPI { ConfigAPI(client: apiClient) }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading config…")
                    .tint(Theme.Colors.cyberBlue)
                    .foregroundStyle(Theme.Colors.silver)
            } else if let err = error {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Error",
                    message: err,
                    action: { Task { await loadConfig() } },
                    actionLabel: "Retry"
                )
            } else {
                configForm
            }
        }
        .navigationTitle("Server Config")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await saveConfig() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.7).tint(Theme.Colors.cyberBlue)
                    } else {
                        Text("Save")
                            .foregroundStyle(Theme.Colors.cyberBlue)
                    }
                }
                .disabled(isSaving || isLoading)
            }
        }
        .task { await loadConfig() }
        .overlay(saveSuccessBanner, alignment: .top)
    }

    // MARK: - Form

    private var configForm: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {

                if let err = saveError {
                    ErrorBanner(error: .network(err), onDismiss: { saveError = nil })
                        .padding(.horizontal, Theme.Spacing.md)
                }

                // Models
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        sectionHeader("Models", icon: "cpu")
                        configField("Default Model", value: $model, hint: "e.g., anthropic/claude-opus-4-5")
                        configField("Small Model", value: $smallModel, hint: "e.g., anthropic/claude-haiku-3-5")
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)

                // General
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        sectionHeader("General", icon: "gearshape")
                        configField("Username", value: $username, hint: "Display name")
                        configField("Log Level", value: $logLevel, hint: "debug, info, warn, error")
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)

                // Features
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        sectionHeader("Features", icon: "switch.2")
                        toggleField("Snapshot", isOn: $snapshot, description: "Auto-snapshot sessions")
                        Divider().background(Theme.Colors.slate)
                        toggleField("Auto Share", isOn: $autoshare, description: "Automatically share sessions")
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)

                // Advanced raw JSON hint
                GlassCard {
                    DisclosureGroup(
                        isExpanded: $showAdvanced,
                        content: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("For advanced configuration (agents, providers, MCP, keybinds), edit the opencode.json config file on the server directly.")
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.silver)
                                    .padding(.top, Theme.Spacing.sm)
                            }
                        },
                        label: {
                            Label("Advanced", systemImage: "wrench.and.screwdriver")
                                .font(Theme.Fonts.captionBold)
                                .foregroundStyle(Theme.Colors.silver)
                        }
                    )
                    .accentColor(Theme.Colors.silver)
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.vertical, Theme.Spacing.lg)
        }
    }

    // MARK: - Row Builders

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(Theme.Fonts.captionBold)
            .foregroundStyle(Theme.Colors.silver)
    }

    private func configField(_ label: String, value: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
            GlassTextField(placeholder: hint, text: value)
        }
    }

    private func toggleField(_ label: String, isOn: Binding<Bool>, description: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.cloud)
                Text(description)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.silver)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .tint(Theme.Colors.neonGreen)
                .labelsHidden()
        }
    }

    // MARK: - Success Banner

    @ViewBuilder
    private var saveSuccessBanner: some View {
        if saveSuccess {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.neonGreen)
                Text("Config saved")
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

    // MARK: - Load / Save

    private func loadConfig() async {
        isLoading = true
        error = nil
        do {
            let c = try await configAPI.get()
            config = c
            populateFields(from: c)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func populateFields(from c: ServerConfig) {
        model = c.model ?? ""
        smallModel = c.smallModel ?? ""
        username = c.username ?? ""
        logLevel = c.logLevel ?? ""
        snapshot = c.snapshot ?? false
        autoshare = c.autoshare ?? false
    }

    private func saveConfig() async {
        isSaving = true
        saveError = nil
        var updated = config ?? ServerConfig()
        updated.model = model.isEmpty ? nil : model
        updated.smallModel = smallModel.isEmpty ? nil : smallModel
        updated.username = username.isEmpty ? nil : username
        updated.logLevel = logLevel.isEmpty ? nil : logLevel
        updated.snapshot = snapshot
        updated.autoshare = autoshare
        do {
            let saved = try await configAPI.update(updated)
            config = saved
            populateFields(from: saved)
            withAnimation {
                saveSuccess = true
            }
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
