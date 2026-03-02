//
//  MCPView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Lists all MCP (Model Context Protocol) servers with their status.
/// Supports connect/disconnect, add new, and swipe to remove.
struct MCPView: View {
    let apiClient: APIClient

    @State private var statusMap: MCPAPI.McpStatusMap = [:]
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var showAddSheet = false
    @State private var pendingAction: String? = nil // name of server being acted upon

    private var mcpAPI: MCPAPI { MCPAPI(client: apiClient) }
    private var sortedServers: [(name: String, status: McpStatus)] {
        statusMap.map { (name: $0.key, status: $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        ZStack {
            Theme.Colors.deepBlack.ignoresSafeArea()

            if isLoading && statusMap.isEmpty {
                ProgressView("Loading MCP servers…")
                    .tint(Theme.Colors.cyberBlue)
                    .foregroundStyle(Theme.Colors.silver)
            } else if let err = error {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Error",
                    message: err,
                    action: { Task { await loadServers() } },
                    actionLabel: "Retry"
                )
            } else if sortedServers.isEmpty {
                EmptyStateView(
                    systemImage: "puzzlepiece.extension",
                    title: "No MCP Servers",
                    message: "Add a Model Context Protocol server to extend AI capabilities.",
                    action: { showAddSheet = true },
                    actionLabel: "Add Server"
                )
            } else {
                serverList
            }
        }
        .navigationTitle("MCP Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            MCPAddView(apiClient: apiClient) {
                Task { await loadServers() }
            }
        }
        .task { await loadServers() }
        .refreshable { await loadServers() }
    }

    // MARK: - Server List

    private var serverList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(sortedServers.enumerated()), id: \.element.name) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.Colors.graphite)
                            .frame(height: 1)
                            .padding(.leading, 20)
                            .padding(.vertical, 2)
                    }
                    MCPServerRow(
                        name: entry.name,
                        status: entry.status,
                        isPending: pendingAction == entry.name,
                        onConnect: { Task { await connect(name: entry.name) } },
                        onDisconnect: { Task { await disconnect(name: entry.name) } }
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await remove(name: entry.name) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
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

    // MARK: - Actions

    private func loadServers() async {
        isLoading = true
        error = nil
        do {
            statusMap = try await mcpAPI.list()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func connect(name: String) async {
        pendingAction = name
        do {
            try await mcpAPI.connect(name: name)
            await loadServers()
        } catch {
            // Silently refresh to show current state
            await loadServers()
        }
        pendingAction = nil
    }

    private func disconnect(name: String) async {
        pendingAction = name
        do {
            try await mcpAPI.disconnect(name: name)
            await loadServers()
        } catch {
            await loadServers()
        }
        pendingAction = nil
    }

    private func remove(name: String) async {
        do {
            try await mcpAPI.remove(name: name)
            statusMap.removeValue(forKey: name)
        } catch {
            await loadServers()
        }
    }
}

// MARK: - MCPServerRow

private struct MCPServerRow: View {
    let name: String
    let status: McpStatus
    let isPending: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Status dot
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.cloud)
                Text(statusLabel)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(statusLabelColor)
            }

            Spacer()

            if isPending {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Theme.Colors.cyberBlue)
            } else {
                actionButton
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .connected:
            Button("Disconnect") { onDisconnect() }
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.hotPink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Theme.Colors.hotPink.opacity(0.12))
                )
        case .disabled, .needsAuth, .needsClientRegistration:
            Button("Connect") { onConnect() }
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.cyberBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Theme.Colors.cyberBlue.opacity(0.12))
                )
        case .failed:
            Button("Retry") { onConnect() }
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.neonOrange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Theme.Colors.neonOrange.opacity(0.12))
                )
        }
    }

    private var dotColor: Color {
        switch status {
        case .connected: return Theme.Colors.neonGreen
        case .disabled: return Theme.Colors.silver
        case .failed: return Theme.Colors.hotPink
        case .needsAuth: return Theme.Colors.neonOrange
        case .needsClientRegistration: return Theme.Colors.electricPurple
        }
    }

    private var statusLabel: String {
        switch status {
        case .connected: return "Connected"
        case .disabled: return "Disabled"
        case .failed(let e): return "Failed: \(e)"
        case .needsAuth: return "Needs authentication"
        case .needsClientRegistration(let e): return "Needs registration: \(e)"
        }
    }

    private var statusLabelColor: Color {
        switch status {
        case .connected: return Theme.Colors.neonGreen
        case .disabled: return Theme.Colors.silver
        case .failed: return Theme.Colors.hotPink
        case .needsAuth: return Theme.Colors.neonOrange
        case .needsClientRegistration: return Theme.Colors.electricPurple
        }
    }
}

// MARK: - MCPAddView

/// Sheet for adding a new MCP server (local or remote).
struct MCPAddView: View {
    let apiClient: APIClient
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var serverType = "local" // "local" or "remote"
    @State private var command = ""         // for local: space-separated command + args
    @State private var remoteURL = ""       // for remote
    @State private var envKey = ""
    @State private var envValue = ""
    @State private var envVars: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String? = nil

    private var mcpAPI: MCPAPI { MCPAPI(client: apiClient) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Name
                        GlassCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                fieldLabel("Server Name")
                                GlassTextField(placeholder: "e.g., filesystem", text: $name)
                            }
                        }

                        // Type picker
                        GlassCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                fieldLabel("Type")
                                Picker("Type", selection: $serverType) {
                                    Text("Local (stdio)").tag("local")
                                    Text("Remote (SSE)").tag("remote")
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // Config
                        GlassCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                if serverType == "local" {
                                    fieldLabel("Command")
                                    GlassTextField(placeholder: "e.g., npx -y @modelcontextprotocol/server-filesystem /path", text: $command)
                                    Text("Space-separated command and arguments")
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.silver)
                                } else {
                                    fieldLabel("URL")
                                    GlassTextField(placeholder: "https://mcp.example.com/sse", text: $remoteURL)
                                }
                            }
                        }

                        // Environment variables (local only)
                        if serverType == "local" {
                            GlassCard {
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    fieldLabel("Environment Variables")

                                    ForEach(envVars.keys.sorted(), id: \.self) { key in
                                        HStack {
                                            Text(key)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(Theme.Colors.neonGreen)
                                            Text("=")
                                                .foregroundStyle(Theme.Colors.silver)
                                            Text(String(repeating: "•", count: min(envVars[key]?.count ?? 0, 8)))
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(Theme.Colors.silver)
                                            Spacer()
                                            Button {
                                                envVars.removeValue(forKey: key)
                                            } label: {
                                                Image(systemName: "minus.circle")
                                                    .foregroundStyle(Theme.Colors.hotPink)
                                            }
                                        }
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Theme.Colors.slate)
                                        )
                                    }

                                    HStack(spacing: Theme.Spacing.sm) {
                                        GlassTextField(placeholder: "KEY", text: $envKey)
                                            .frame(maxWidth: 100)
                                        GlassTextField(placeholder: "value", text: $envValue)
                                        Button {
                                            guard !envKey.isEmpty else { return }
                                            envVars[envKey] = envValue
                                            envKey = ""
                                            envValue = ""
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(Theme.Colors.cyberBlue)
                                                .font(.title3)
                                        }
                                    }
                                }
                            }
                        }

                        if let err = saveError {
                            Text(err)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.hotPink)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Add MCP Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("Add")
                                .foregroundStyle(Theme.Colors.cyberBlue)
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
    }

    private var isValid: Bool {
        !name.isEmpty && (serverType == "local" ? !command.isEmpty : !remoteURL.isEmpty)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.captionBold)
            .foregroundStyle(Theme.Colors.silver)
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            let config: McpConfig
            if serverType == "local" {
                let parts = command.split(separator: " ").map(String.init)
                config = .local(McpLocalConfig(
                    type: "local",
                    command: parts,
                    environment: envVars.isEmpty ? nil : envVars
                ))
            } else {
                config = .remote(McpRemoteConfig(type: "remote", url: remoteURL))
            }
            try await mcpAPI.add(name: name, config: config)
            onAdded()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
