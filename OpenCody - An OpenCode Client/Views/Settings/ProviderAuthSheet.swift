//
//  ProviderAuthSheet.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Connects a provider by storing an API key.
///
/// ## Why only an API key
///
/// The server also advertises OAuth flows for a few providers — signing into a
/// ChatGPT Pro/Plus or Copilot account through the browser. OpenCody deliberately does
/// not drive those: an in-app flow that signs a user into a subscription bought
/// elsewhere is the kind of thing App Review reads as access to externally purchased
/// content. Anyone who wants an OAuth provider can run `opencode auth login` on the
/// server; the credential lands in the same store and OpenCody picks it up.
///
/// So one path covers everything: `PUT /auth/{providerID}` with `{type: "api", key}`.
/// That works for any provider ID, including the ~170 with no auth plugin at all, and
/// it is exactly what the reference desktop client does for key-based methods — it
/// ignores such a method's `prompts` and stores the bare key too.
struct ProviderAuthSheet: View {
    let entry: ProviderEntry
    let model: ProvidersViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var isBusy = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        if entry.supportsApiKey {
                            keyForm
                        } else {
                            oauthOnlyNote
                        }

                        if let errorText {
                            Text(errorText)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.hotPink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Spacing.xs)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Connect \(entry.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(entry.supportsApiKey ? "Cancel" : "Close") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
    }

    // MARK: - Key Form

    private var keyForm: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    fieldLabel("API Key")
                    GlassTextField(
                        placeholder: "Paste your key",
                        text: $apiKey,
                        isSecure: true,
                        autocapitalization: .never
                    )
                    hintText("Stored in the opencode server's credential store, not on this device.")
                    if let hint = entry.envVarHint {
                        hintText("Alternatively set \(hint) in the server's environment.")
                    }
                }

                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isBusy {
                            ProgressView().scaleEffect(0.7).tint(Theme.Colors.onPrimaryAccent)
                        }
                        Text("Save Key")
                    }
                    .frame(maxWidth: .infinity)
                }
                .primaryButton()
                .disabled(isBusy || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - OAuth-only Providers

    /// Shown for a provider whose only auth methods are OAuth flows.
    ///
    /// Storing a key for one of these would put it in the server's `connected` list —
    /// that list only checks whether an auth entry exists — while every actual request
    /// failed. A note beats a field that produces a broken connection.
    private var oauthOnlyNote: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.neonOrange)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Needs a browser sign-in")
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.cloud)
                        Text("\(entry.name) does not accept a plain API key — it only offers \(methodLabels). OpenCody can't run that flow, so connect it on the server instead.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.silver)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    fieldLabel("On the server, run")
                    Text("opencode auth login")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.cloud)
                        .textSelection(.enabled)
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.small)
                                .fill(Theme.Colors.fillStrong)
                        )
                    hintText("The credential lands in the same store, and OpenCody picks it up on the next refresh.")
                }
            }
        }
    }

    private var methodLabels: String {
        let labels = entry.authMethods.map(\.label)
        return labels.count == 1 ? labels[0] : labels.joined(separator: " or ")
    }

    // MARK: - Actions

    private func save() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            try await model.setApiKey(
                providerID: entry.id,
                key: apiKey.trimmingCharacters(in: .whitespaces)
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Small Views

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.captionBold)
            .foregroundStyle(Theme.Colors.silver)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.silver)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
