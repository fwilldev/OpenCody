//
//  EditServerView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI
import SwiftUI

// MARK: - EditServerView

struct EditServerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var serverStore: ServerStoreModel

    @Bindable var server: ServerConnection
    let connectionManager: ConnectionManager

    // MARK: - Form State

    @State private var password: String = ""
    @State private var port: String = ""
    @State private var showDeleteConfirmation: Bool = false

    // MARK: - Test Connection

    @State private var testState: TestConnectionState = .idle

    enum TestConnectionState: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    // MARK: - Computed

    private var urlPreview: String {
        let scheme = server.useHTTPS ? "https" : "http"
        let host = server.hostname.isEmpty ? "hostname" : server.hostname
        let portValue = port.isEmpty ? "4096" : port
        return "\(scheme)://\(host):\(portValue)"
    }

    private var canSave: Bool {
        !server.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !server.hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && (Int(port) ?? 0) > 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    headerSection
                    formSection
                    urlPreviewSection
                    testConnectionSection
                    saveSection
                    deleteSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Colors.deepBlack)
            .navigationTitle("Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
            .onAppear {
                port = String(server.port)
                password = (try? KeychainService.retrieve(for: server.keychainIdentifier)) ?? ""
            }
            .confirmationDialog(
                "Delete Server",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteServer()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove \"\(server.name)\" and its saved credentials.")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.electricPurple)
                .shadow(color: Theme.Colors.electricPurple.opacity(0.4), radius: 8)

            Text("Edit Server")
                .font(Theme.Fonts.title2)
                .foregroundStyle(Theme.Colors.cloud)

            Text("Update your server connection settings.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var formSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            fieldGroup(label: "Name") {
                GlassTextField(
                    placeholder: "My Server",
                    text: $server.name,
                    autocapitalization: .words
                )
            }

            fieldGroup(label: "Hostname") {
                GlassTextField(
                    placeholder: "192.168.1.100",
                    text: $server.hostname,
                    keyboardType: .URL,
                    autocapitalization: .never
                )
            }

            fieldGroup(label: "Port") {
                GlassTextField(
                    placeholder: "4096",
                    text: $port,
                    keyboardType: .numberPad,
                    autocapitalization: .never
                )
            }

            HStack {
                Text("Use HTTPS")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.cloud)
                Spacer()
                Toggle("", isOn: $server.useHTTPS)
                    .labelsHidden()
                    .tint(Theme.Colors.cyberBlue)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .glassCard(radius: Theme.Radius.small)

            fieldGroup(label: "Username") {
                GlassTextField(
                    placeholder: "admin",
                    text: $server.username,
                    autocapitalization: .never
                )
            }

            fieldGroup(label: "Password") {
                GlassTextField(
                    placeholder: "Password",
                    text: $password,
                    isSecure: true
                )
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    private var urlPreviewSection: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "link")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.cyberBlue)

            Text(urlPreview)
                .font(Theme.Fonts.codeCaption)
                .foregroundStyle(Theme.Colors.silver)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .glassCard(radius: Theme.Radius.small)
    }

    private var testConnectionSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                testConnection()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if testState == .testing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Theme.Colors.neonOrange)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text("Test Connection")
                }
                .frame(maxWidth: .infinity)
            }
            .secondaryButton()
            .disabled(server.hostname.isEmpty || testState == .testing)

            testStateIndicator
        }
    }

    @ViewBuilder
    private var testStateIndicator: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: Theme.Spacing.xs) {
                Text("Connecting...")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.neonOrange)
            }
        case .success:
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Theme.Colors.neonGreen)
                Text("Connection successful")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.neonGreen)
            }
            .transition(.opacity.combined(with: .scale))
        case .failure(let message):
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Colors.hotPink)
                Text(message)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.hotPink)
                    .lineLimit(2)
            }
            .transition(.opacity.combined(with: .scale))
        }
    }

    private var saveSection: some View {
        Button {
            saveChanges()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark")
                Text("Save Changes")
            }
            .frame(maxWidth: .infinity)
        }
        .primaryButton()
        .disabled(!canSave)
        .opacity(canSave ? 1.0 : 0.5)
    }

    private var deleteSection: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "trash")
                Text("Delete Server")
            }
            .frame(maxWidth: .infinity)
        }
        .destructiveButton()
    }

    // MARK: - Helpers

    private func fieldGroup(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
            content()
        }
    }

    // MARK: - Actions

    private func testConnection() {
        let portNumber = Int(port) ?? 4096
        let testServer = ServerConnection(
            name: server.name.isEmpty ? "Test" : server.name,
            hostname: server.hostname,
            port: portNumber,
            useHTTPS: server.useHTTPS,
            username: server.username
        )

        withAnimation { testState = .testing }

        Task {
            do {
                try await connectionManager.connect(server: testServer, password: password)
                connectionManager.disconnect(serverID: testServer.id)
                withAnimation { testState = .success }
            } catch {
                withAnimation { testState = .failure(error.localizedDescription) }
            }
        }
    }

    private func saveChanges() {
        server.port = Int(port) ?? 4096
        server.name = server.name.trimmingCharacters(in: .whitespaces)
        server.hostname = server.hostname.trimmingCharacters(in: .whitespaces)
        server.username = server.username.trimmingCharacters(in: .whitespaces)

        try? KeychainService.save(password: password, for: server.keychainIdentifier)
        serverStore.update(server)
        dismiss()
    }

    private func deleteServer() {
        connectionManager.disconnect(serverID: server.id)
        try? KeychainService.delete(for: server.keychainIdentifier)
        serverStore.delete(id: server.id)
        dismiss()
    }
}
