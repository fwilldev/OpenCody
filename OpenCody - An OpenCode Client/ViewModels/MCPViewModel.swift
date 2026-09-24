//
//  MCPViewModel.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - MCPServerEntry

/// One MCP server as the settings screen sees it: its live status, plus its
/// definition when that definition lives somewhere this app can edit.
struct MCPServerEntry: Identifiable, Sendable {
    let name: String
    /// Live status from `GET /mcp`. Absent for a server that is declared in the
    /// global config but not known to the instance yet.
    var status: McpStatus?
    /// The definition from the global opencode config, when it is declared there.
    var globalConfig: McpConfig?

    var id: String { name }

    /// Where this server's definition lives.
    enum Origin: Sendable {
        /// Declared in `~/.config/opencode/opencode.json` — editable from here.
        case global
        /// Declared in a project config file, or added at runtime via `POST /mcp`.
        /// Read-only from here; the app has no write access to those sources.
        case external
    }

    var origin: Origin { globalConfig == nil ? .external : .global }
    var isEditable: Bool { origin == .global }

    /// Effective status for display — a server declared in the config but not yet
    /// known to the instance reads as disabled rather than as a blank row.
    var displayStatus: McpStatus {
        status ?? .disabled
    }

    /// What this server connects to, for the row subtitle.
    var summary: String? {
        globalConfig?.summary ?? nil
    }
}

// MARK: - MCPViewModel

/// Loads, edits and persists MCP server definitions.
///
/// Reads two sources and joins them by name: `GET /mcp` for live status and
/// `GET /global/config` for the definitions the app can edit. Writes go through
/// `MCPConfigWriter`, which explains why the global config is the only viable
/// persistence target.
@Observable
@MainActor
final class MCPViewModel {

    // MARK: - Observable State

    var entries: [MCPServerEntry] = []
    var isLoading = true
    /// Set when the initial load failed and there is nothing to show.
    var loadError: String? = nil
    /// Transient message for a failed or partially-applied action.
    var banner: BannerMessage? = nil
    /// Names of servers with an action in flight.
    var pending: Set<String> = []

    struct BannerMessage: Identifiable, Sendable {
        let id = UUID()
        let text: String
        var isWarning: Bool = true
    }

    // MARK: - Dependencies

    @ObservationIgnored private let apiClient: APIClient
    /// The workspace whose MCP configuration is being inspected.
    ///
    /// Every MCP route is instance-scoped: without this, calls land on the instance
    /// for the server's own working directory, which resolves a different config
    /// chain and therefore a different set of servers.
    @ObservationIgnored private let directory: String?

    @ObservationIgnored private var mcpAPI: MCPAPI { MCPAPI(client: apiClient) }
    @ObservationIgnored private var writer: MCPConfigWriter { MCPConfigWriter(client: apiClient) }

    // MARK: - Init

    init(apiClient: APIClient, directory: String? = nil) {
        self.apiClient = apiClient
        self.directory = directory
    }

    // MARK: - Loading

    func load() async {
        loadError = nil
        defer { isLoading = false }

        // Status and config are independent; a failure in either should not blank the
        // other. Status is the one that matters for the screen to be usable at all.
        async let statusTask = mcpAPI.list(directory: directory)
        async let configTask = writer.loadGlobalServers()

        // Await the optional source first — an early return would cancel it.
        var globalServers: [String: McpConfig] = [:]
        var configError: String? = nil
        do {
            globalServers = try await configTask
        } catch {
            configError = error.localizedDescription
        }

        let statusMap: MCPAPI.McpStatusMap
        do {
            statusMap = try await statusTask
        } catch {
            // Nothing worth showing without a status list.
            loadError = error.localizedDescription
            entries = []
            return
        }

        if let configError {
            banner = BannerMessage(
                text: "Server statuses loaded, but the global config could not be read — editing is unavailable. \(configError)"
            )
        }

        let names = Set(statusMap.keys).union(globalServers.keys)
        entries = names
            .map { MCPServerEntry(name: $0, status: statusMap[$0], globalConfig: globalServers[$0]) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Live Actions

    /// Connect a server in the running instance. Not persistent — it flips runtime
    /// state, it does not change `enabled` in the config.
    func connect(name: String) async {
        await perform(name) { try await self.mcpAPI.connect(name: name, directory: self.directory) }
    }

    /// Disconnect a server in the running instance. Not persistent.
    func disconnect(name: String) async {
        await perform(name) { try await self.mcpAPI.disconnect(name: name, directory: self.directory) }
    }

    /// Clear stored OAuth credentials so the server re-authenticates on next connect.
    func signOut(name: String) async {
        await perform(name) { try await self.mcpAPI.removeOAuth(name: name, directory: self.directory) }
    }

    // MARK: - Persistent Actions

    /// Create or overwrite a server definition in the global config.
    func save(name: String, config: McpConfig, previous: McpConfig?) async throws {
        let result = try await writer.save(name: name, config: config, previous: previous)
        if !result.isClean {
            banner = BannerMessage(
                text: "Saved, but \(result.strandedKeys.joined(separator: ", ")) could not be removed — the server merges config writes and cannot delete keys. Remove them in the config file to be rid of them."
            )
        }
        await reloadAfterConfigWrite()
    }

    /// Enable or disable a server persistently.
    func setEnabled(name: String, enabled: Bool) async {
        guard let entry = entries.first(where: { $0.name == name }), let config = entry.globalConfig else { return }
        pending.insert(name)
        defer { pending.remove(name) }
        do {
            try await writer.setEnabled(name: name, config: config, enabled: enabled)
            await reloadAfterConfigWrite()
        } catch {
            banner = BannerMessage(text: error.localizedDescription)
            await load()
        }
    }

    // MARK: - Private

    private func perform(_ name: String, _ action: @escaping () async throws -> Void) async {
        pending.insert(name)
        defer { pending.remove(name) }
        do {
            try await action()
        } catch {
            // Surface it: a silent refresh looks like the tap did nothing.
            banner = BannerMessage(text: error.localizedDescription)
        }
        await load()
    }

    /// Reload after a config write.
    ///
    /// A successful global config write makes the server dispose every instance, and it
    /// does so on a forked fiber — so a reload issued immediately can still be answered
    /// by the outgoing instance with pre-write data. The follow-up reload catches the
    /// rebuilt instance, and runs detached so the caller (a sheet waiting to dismiss)
    /// does not sit on a spinner for it.
    private func reloadAfterConfigWrite() async {
        await load()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            await self?.load()
        }
    }
}
