//
//  MCPServerEditView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

// MARK: - CommandLine Tokenizer

/// Splits a command line into argv the way a shell would, for the subset that matters.
///
/// The server takes `command` as an array, so the text the user types has to be split
/// somewhere. Splitting on spaces breaks the moment a path contains one — which is
/// routine for `--directory /Users/me/My Projects/x` — so quoting and backslash
/// escapes are honoured here.
enum CommandTokenizer {
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasCurrent = false
        var quote: Character? = nil
        var escaped = false

        for char in input {
            if escaped {
                current.append(char)
                hasCurrent = true
                escaped = false
                continue
            }
            // Inside single quotes a backslash is literal, as in POSIX shells.
            if char == "\\" && quote != "'" {
                escaped = true
                hasCurrent = true
                continue
            }
            if let open = quote {
                if char == open {
                    quote = nil
                } else {
                    current.append(char)
                }
                hasCurrent = true
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                hasCurrent = true
                continue
            }
            if char.isWhitespace {
                if hasCurrent {
                    tokens.append(current)
                    current = ""
                    hasCurrent = false
                }
                continue
            }
            current.append(char)
            hasCurrent = true
        }

        if hasCurrent { tokens.append(current) }
        return tokens
    }

    /// Render argv back into an editable line, quoting what needs it.
    static func render(_ tokens: [String]) -> String {
        tokens.map { token in
            if token.isEmpty { return "''" }
            let needsQuoting = token.contains { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" }
            guard needsQuoting else { return token }
            let escaped = token
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        .joined(separator: " ")
    }
}

// MARK: - MCPServerEditView

/// Create or edit one MCP server definition, saved into the global opencode config.
struct MCPServerEditView: View {

    /// What the sheet is doing — creating a new entry, or editing an existing one.
    enum Mode {
        case create
        case edit(name: String, config: McpConfig)

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    let mode: Mode
    /// Names already in use, so a new entry cannot silently overwrite one.
    let existingNames: Set<String>
    let onSave: (String, McpConfig, McpConfig?) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var name = ""
    @State private var isRemote = false
    @State private var commandLine = ""
    @State private var cwd = ""
    @State private var url = ""
    @State private var timeoutText = ""
    @State private var isEnabled = true
    @State private var pairs: [KeyValuePair] = []
    @State private var isSaving = false
    @State private var saveError: String? = nil

    /// An environment variable or header row. Identity is stable across edits so the
    /// text fields keep focus while typing, which a `[String: String]` cannot do.
    private struct KeyValuePair: Identifiable, Equatable {
        let id = UUID()
        var key: String = ""
        var value: String = ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        identitySection
                        connectionSection
                        pairsSection
                        advancedSection
                        persistenceNote

                        if let saveError {
                            Text(saveError)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.hotPink)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Spacing.xs)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .navigationTitle(mode.isEditing ? "Edit Server" : "Add MCP Server")
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
                            Text("Save").foregroundStyle(Theme.Colors.cyberBlue)
                        }
                    }
                    .disabled(validationError != nil || isSaving)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .onAppear(perform: populate)
    }

    // MARK: - Sections

    private var identitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("Server Name")
                if mode.isEditing {
                    Text(name)
                        .font(Theme.Fonts.code)
                        .foregroundStyle(Theme.Colors.cloud)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.xs)
                    hint("The name is the config key and cannot be changed here.")
                } else {
                    GlassTextField(
                        placeholder: "e.g. filesystem",
                        text: $name,
                        autocapitalization: .never
                    )
                    if let nameError { warning(nameError) }
                }

                Divider().background(Theme.Colors.slate).padding(.vertical, Theme.Spacing.xs)

                Toggle(isOn: $isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enabled").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.cloud)
                        Text("Connect this server on startup")
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.silver)
                    }
                }
                .tint(Theme.Colors.cyberBlue)
            }
        }
    }

    private var connectionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("Type")
                Picker("Type", selection: $isRemote) {
                    Text("Local (stdio)").tag(false)
                    Text("Remote (HTTP)").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(mode.isEditing)

                if mode.isEditing {
                    hint("Switching type would leave the old type's keys behind in the config file — create a new server instead.")
                }

                Divider().background(Theme.Colors.slate).padding(.vertical, Theme.Spacing.xs)

                if isRemote {
                    fieldLabel("URL")
                    GlassTextField(
                        placeholder: "https://mcp.example.com/mcp",
                        text: $url,
                        keyboardType: .URL,
                        autocapitalization: .never
                    )
                    if let urlError { warning(urlError) }
                } else {
                    fieldLabel("Command")
                    GlassTextField(
                        placeholder: "npx -y @modelcontextprotocol/server-filesystem /srv/project",
                        text: $commandLine,
                        autocapitalization: .never
                    )
                    argvPreview

                    fieldLabel("Working Directory").padding(.top, Theme.Spacing.xs)
                    GlassTextField(
                        placeholder: "Optional — defaults to the workspace",
                        text: $cwd,
                        autocapitalization: .never
                    )
                }
            }
        }
    }

    /// Show exactly what will be sent as `command`, so a mis-quoted path is visible
    /// before the server fails to spawn the process.
    @ViewBuilder
    private var argvPreview: some View {
        let tokens = CommandTokenizer.tokenize(commandLine)
        if tokens.isEmpty {
            hint("Command and arguments, quoted like in a shell.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                hint("Runs as \(tokens.count) argument\(tokens.count == 1 ? "" : "s"):")
                HStack(spacing: 4) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                        Text(token)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.Colors.cloud)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.Colors.fillStrong))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pairsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel(isRemote ? "Headers" : "Environment Variables")
                hint(isRemote
                     ? "Sent with every request — e.g. Authorization: Bearer …"
                     : "Set in the server process's environment.")

                ForEach($pairs) { $pair in
                    HStack(spacing: Theme.Spacing.sm) {
                        GlassTextField(
                            placeholder: isRemote ? "Authorization" : "API_KEY",
                            text: $pair.key,
                            autocapitalization: .never
                        )
                        .frame(maxWidth: 130)
                        GlassTextField(
                            placeholder: "value",
                            text: $pair.value,
                            autocapitalization: .never
                        )
                        Button {
                            pairs.removeAll { $0.id == pair.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.Colors.hotPink)
                        }
                    }
                }

                Button {
                    pairs.append(KeyValuePair())
                } label: {
                    Label(isRemote ? "Add Header" : "Add Variable", systemImage: "plus.circle.fill")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
                .padding(.top, Theme.Spacing.xs)

                if !strandedKeys.isEmpty {
                    warning("Removing \(strandedKeys.joined(separator: ", ")) will not take effect — the server merges config writes and cannot delete keys. Edit the config file to drop them.")
                }
            }
        }
    }

    private var advancedSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("Request Timeout")
                GlassTextField(
                    placeholder: "Milliseconds — server default is 5000",
                    text: $timeoutText,
                    keyboardType: .numberPad
                )
                if let timeoutError { warning(timeoutError) }
            }
        }
    }

    private var persistenceNote: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.cyberBlue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved to the global opencode config")
                    .font(Theme.Fonts.captionBold)
                    .foregroundStyle(Theme.Colors.silver)
                Text("Applies to every project on this server. Saving restarts the server's instances, which interrupts any session that is mid-turn.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.silver)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.Colors.fillSubtle))
    }

    // MARK: - Validation

    private var nameError: String? {
        // The edited server's own name is in `existingNames`; only a *new* name can collide.
        guard !mode.isEditing else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if existingNames.contains(trimmed) { return "A server named \(trimmed) already exists." }
        return nil
    }

    private var urlError: String? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https", parsed.host != nil else {
            return "Needs to be an http(s) URL."
        }
        return nil
    }

    private var timeoutError: String? {
        let trimmed = timeoutText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else { return "Must be a positive number of milliseconds." }
        return nil
    }

    /// Keys the user removed from an existing definition. The server's merge keeps
    /// them, so the sheet warns rather than pretending the removal worked.
    private var strandedKeys: [String] {
        guard case .edit(_, let previous) = mode else { return [] }
        let current = Set(pairs.map { $0.key.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let before: [String: String]?
        switch previous {
        case .local(let c): before = c.environment
        case .remote(let c): before = c.headers
        case .enabledOverride: before = nil
        }
        return (before ?? [:]).keys.filter { !current.contains($0) }.sorted()
    }

    private var validationError: String? {
        if nameError != nil || urlError != nil || timeoutError != nil { return "invalid" }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "missing name" }
        if isRemote {
            if url.trimmingCharacters(in: .whitespaces).isEmpty { return "missing url" }
        } else {
            if CommandTokenizer.tokenize(commandLine).isEmpty { return "missing command" }
        }
        // A key with no name would be written as an empty config key.
        if pairs.contains(where: { $0.key.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.isEmpty }) {
            return "unnamed pair"
        }
        return nil
    }

    // MARK: - Populate & Save

    private func populate() {
        guard case .edit(let existingName, let config) = mode else { return }
        name = existingName
        isEnabled = config.isEnabled

        switch config {
        case .local(let local):
            isRemote = false
            commandLine = CommandTokenizer.render(local.command)
            cwd = local.cwd ?? ""
            timeoutText = local.timeout.map(String.init) ?? ""
            pairs = (local.environment ?? [:]).sorted { $0.key < $1.key }
                .map { KeyValuePair(key: $0.key, value: $0.value) }
        case .remote(let remote):
            isRemote = true
            url = remote.url
            timeoutText = remote.timeout.map(String.init) ?? ""
            pairs = (remote.headers ?? [:]).sorted { $0.key < $1.key }
                .map { KeyValuePair(key: $0.key, value: $0.value) }
        case .enabledOverride:
            // An override carries no connection details; treat it as a fresh local server.
            isRemote = false
        }
    }

    private func buildConfig() -> McpConfig {
        let collected = Dictionary(
            pairs
                .map { ($0.key.trimmingCharacters(in: .whitespaces), $0.value) }
                .filter { !$0.0.isEmpty },
            uniquingKeysWith: { _, last in last }
        )
        let timeout = Int(timeoutText.trimmingCharacters(in: .whitespaces))

        if isRemote {
            var remote = McpRemoteConfig(
                url: url.trimmingCharacters(in: .whitespaces),
                enabled: isEnabled,
                headers: collected.isEmpty ? nil : collected,
                timeout: timeout
            )
            // Preserve OAuth settings the app does not edit rather than dropping them.
            if case .edit(_, .remote(let previous)) = mode {
                remote.oauth = previous.oauth
            }
            return .remote(remote)
        }

        let trimmedCwd = cwd.trimmingCharacters(in: .whitespaces)
        return .local(McpLocalConfig(
            command: CommandTokenizer.tokenize(commandLine),
            cwd: trimmedCwd.isEmpty ? nil : trimmedCwd,
            environment: collected.isEmpty ? nil : collected,
            enabled: isEnabled,
            timeout: timeout
        ))
    }

    private func save() async {
        isSaving = true
        saveError = nil
        let previous: McpConfig? = {
            if case .edit(_, let config) = mode { return config }
            return nil
        }()
        do {
            try await onSave(name.trimmingCharacters(in: .whitespaces), buildConfig(), previous)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: - Small Views

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.captionBold)
            .foregroundStyle(Theme.Colors.silver)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.silver)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.neonOrange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
