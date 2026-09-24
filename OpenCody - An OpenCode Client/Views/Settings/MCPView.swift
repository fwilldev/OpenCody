//
//  MCPView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Lists the MCP (Model Context Protocol) servers configured on the opencode server,
/// and lets the ones declared in the global config be created, edited and toggled.
///
/// Two kinds of row appear here and they behave differently on purpose:
///
/// - Servers from the **global** config can be edited and persistently enabled or
///   disabled, because the app can write that file.
/// - Servers from a **project** config (or added at runtime) are read-only. The app
///   has no write path to those sources, so offering an edit button would be a lie;
///   the row says where the definition lives instead.
struct MCPView: View {
    let apiClient: APIClient
    /// The workspace whose MCP config should be inspected. MCP routes are
    /// instance-scoped, so without this the screen shows the server's own cwd instance.
    var directory: String? = nil

    @State private var model: MCPViewModel
    @State private var editing: MCPServerEditView.Mode? = nil

    init(apiClient: APIClient, directory: String? = nil) {
        self.apiClient = apiClient
        self.directory = directory
        _model = State(initialValue: MCPViewModel(apiClient: apiClient, directory: directory))
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
                    systemImage: "puzzlepiece.extension",
                    title: "No MCP Servers",
                    message: "Add a Model Context Protocol server to give the agent more tools.",
                    action: { editing = .create },
                    actionLabel: "Add Server"
                )
            } else {
                serverList
            }
        }
        .overlay(alignment: .top) { bannerOverlay }
        .navigationTitle("MCP Servers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editing = .create
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
        }
        .sheet(item: $editing) { mode in
            MCPServerEditView(
                mode: mode,
                existingNames: Set(model.entries.map(\.name)),
                onSave: { name, config, previous in
                    try await model.save(name: name, config: config, previous: previous)
                }
            )
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    // MARK: - Banner

    @ViewBuilder
    private var bannerOverlay: some View {
        if let banner = model.banner {
            ErrorBanner(
                error: .validation(0, banner.text),
                onDismiss: { model.banner = nil }
            )
            // Keyed on the message: `ErrorBanner` animates itself in from `onAppear`,
            // so without a fresh identity a replacement message would swap in silently.
            .id(banner.id)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Server List

    private var serverList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.Colors.graphite)
                            .frame(height: 1)
                            .padding(.leading, 20)
                            .padding(.vertical, 2)
                    }
                    MCPServerRow(
                        entry: entry,
                        isPending: model.pending.contains(entry.name),
                        onConnect: { Task { await model.connect(name: entry.name) } },
                        onDisconnect: { Task { await model.disconnect(name: entry.name) } },
                        onEdit: {
                            if let config = entry.globalConfig {
                                editing = .edit(name: entry.name, config: config)
                            }
                        },
                        onSetEnabled: { enabled in
                            Task { await model.setEnabled(name: entry.name, enabled: enabled) }
                        },
                        onSignOut: { Task { await model.signOut(name: entry.name) } }
                    )
                }
            }
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.carbon))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.graphite, lineWidth: 1))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)

            footerNote
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Servers are stored in the opencode config on your server. Removing one entirely is not possible over the API — disable it here, or delete its entry from the config file.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
    }

    // MARK: - Loading

    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Theme.Colors.graphite).frame(height: 1).padding(.leading, 20)
                }
                HStack(spacing: Theme.Spacing.md) {
                    Circle().fill(Theme.Colors.fillMuted).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 120, height: 13)
                        SkeletonBlock(width: 190, height: 10)
                    }
                    Spacer()
                    SkeletonBlock(width: 74, height: 24, cornerRadius: 12)
                }
                .padding(.vertical, 10)
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

// MARK: - Sheet Item Helper

extension MCPServerEditView.Mode: Identifiable {
    var id: String {
        switch self {
        case .create: return "__create__"
        case .edit(let name, _): return "edit:\(name)"
        }
    }
}

// MARK: - MCPServerRow

private struct MCPServerRow: View {
    let entry: MCPServerEntry
    let isPending: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onEdit: () -> Void
    let onSetEnabled: (Bool) -> Void
    let onSignOut: () -> Void

    @State private var showsDetail = false

    private var status: McpStatus { entry.displayStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.cloud)
                        if entry.origin == .external {
                            Text("read-only")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.Colors.silver)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.Colors.fillStrong))
                        }
                    }
                    Text(statusLabel)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(statusColor)
                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Colors.silver)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
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

            // Failure detail and the dead ends get an explanation rather than a
            // button that cannot work.
            if let detail = status.errorDetail {
                DisclosureGroup(isExpanded: $showsDetail) {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.silver)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.xs)
                } label: {
                    Text("Details")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
                .tint(Theme.Colors.cyberBlue)
            }

            if let guidance {
                Text(guidance)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.silver)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            if entry.isEditable {
                Button { onEdit() } label: { Label("Edit", systemImage: "slider.horizontal.3") }

                if entry.globalConfig?.isEnabled == true {
                    Button { onSetEnabled(false) } label: {
                        Label("Disable Permanently", systemImage: "pause.circle")
                    }
                } else {
                    Button { onSetEnabled(true) } label: {
                        Label("Enable Permanently", systemImage: "play.circle")
                    }
                }
            }

            if status.isConnected {
                Button { onDisconnect() } label: { Label("Disconnect", systemImage: "bolt.slash") }
            } else {
                Button { onConnect() } label: { Label("Connect", systemImage: "bolt") }
            }

            Button(role: .destructive) { onSignOut() } label: {
                Label("Remove Saved Login", systemImage: "person.badge.minus")
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .connected:
            pill("Disconnect", color: Theme.Colors.hotPink, action: onDisconnect)
        case .disabled:
            pill("Connect", color: Theme.Colors.cyberBlue, action: onConnect)
        case .failed, .unknown:
            pill("Retry", color: Theme.Colors.neonOrange, action: onConnect)
        case .needsAuth, .needsClientRegistration:
            // Reconnecting cannot resolve either state — the server would report the
            // same status straight back. Editing the config is the way forward.
            if entry.isEditable {
                pill("Configure", color: Theme.Colors.electricPurple, action: onEdit)
            }
        }
    }

    private func pill(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Theme.Fonts.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Labels

    /// Why a row is stuck, when it is stuck for a reason the user can act on.
    private var guidance: String? {
        switch status {
        case .needsAuth:
            return entry.isEditable
                ? "This server wants OAuth. Add a bearer token under Headers, or set up OAuth credentials in the config file."
                : "This server wants OAuth. Its definition lives in a project config, so authenticate it there or on the server."
        case .needsClientRegistration:
            return "Dynamic client registration failed. Set clientId and clientSecret for this server in the config file."
        default:
            if entry.origin == .external, entry.globalConfig == nil {
                return "Defined in a project config file or added at runtime — not editable from here."
            }
            return nil
        }
    }

    private var statusLabel: String {
        switch status {
        case .connected: return "Connected"
        case .disabled: return entry.globalConfig?.isEnabled == false ? "Disabled in config" : "Not connected"
        case .failed: return "Failed"
        case .needsAuth: return "Needs authentication"
        case .needsClientRegistration: return "Needs client registration"
        case .unknown(let raw): return "Unknown status: \(raw)"
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return Theme.Colors.neonGreen
        case .disabled: return Theme.Colors.silver
        case .failed: return Theme.Colors.hotPink
        case .needsAuth: return Theme.Colors.neonOrange
        case .needsClientRegistration: return Theme.Colors.electricPurple
        case .unknown: return Theme.Colors.silver
        }
    }

    private var dotColor: Color { statusColor }
}
