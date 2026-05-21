//
//  AddServerView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI
import SwiftUI

// MARK: - AddServerView

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var serverStore: ServerStoreModel

    let connectionManager: ConnectionManager

    // MARK: - Form State

    @State private var name: String = ""
    @State private var hostname: String = ""
    @State private var port: String = ""
    @State private var useHTTPS: Bool = false
    @State private var username: String = ""
    @State private var password: String = ""

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
        let scheme = useHTTPS ? "https" : "http"
        let host = hostname.isEmpty ? "hostname" : hostname
        if let portInt = Int(port), !port.isEmpty {
            return "\(scheme)://\(host):\(portInt)"
        }
        return "\(scheme)://\(host)"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !hostname.trimmingCharacters(in: .whitespaces).isEmpty
            && (port.isEmpty || (Int(port) != nil && (Int(port) ?? 0) > 0))
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
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Colors.deepBlack)
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.cyberBlue)
                .shadow(color: Theme.Colors.cyberBlue.opacity(0.4), radius: 8)

            Text("New Server")
                .font(Theme.Fonts.title2)
                .foregroundStyle(Theme.Colors.cloud)

            Text("Configure a connection to your OpenCode server.")
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
                    text: $name,
                    autocapitalization: .words
                )
            }

            fieldGroup(label: "Hostname") {
                GlassTextField(
                    placeholder: "192.168.1.100",
                    text: $hostname,
                    keyboardType: .URL,
                    autocapitalization: .never
                )
            }

            fieldGroup(label: "Port (optional)") {
                GlassTextField(
                    placeholder: "Default",
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
                Toggle("", isOn: $useHTTPS)
                    .labelsHidden()
                    .tint(Theme.Colors.cyberBlue)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .glassCard(radius: Theme.Radius.small)

            fieldGroup(label: "Username") {
                GlassTextField(
                    placeholder: "admin",
                    text: $username,
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
            .disabled(hostname.isEmpty || testState == .testing)

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
            saveServer()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark")
                Text("Save Server")
            }
            .frame(maxWidth: .infinity)
        }
        .primaryButton()
        .disabled(!canSave)
        .opacity(canSave ? 1.0 : 0.5)
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
        let portNumber = port.isEmpty ? nil : Int(port)
        let server = ServerConnection(
            name: name.isEmpty ? "Test" : name,
            hostname: hostname,
            port: portNumber,
            useHTTPS: useHTTPS,
            username: username
        )

        withAnimation { testState = .testing }

        Task {
            do {
                try await connectionManager.connect(server: server, password: password)
                // Disconnect after test — this was just a connectivity check
                connectionManager.disconnect(serverID: server.id)
                withAnimation { testState = .success }
            } catch {
                withAnimation { testState = .failure(error.localizedDescription) }
            }
        }
    }

    private func saveServer() {
        let portNumber = port.isEmpty ? nil : Int(port)
        let connection = ServerConnection(
            name: name.trimmingCharacters(in: .whitespaces),
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: portNumber,
            useHTTPS: useHTTPS,
            username: username.trimmingCharacters(in: .whitespaces)
        )

        try? KeychainService.save(password: password, for: connection.keychainIdentifier)
        serverStore.add(connection)
        connectionManager.connectAndActivate(server: connection)
        dismiss()
    }
}
