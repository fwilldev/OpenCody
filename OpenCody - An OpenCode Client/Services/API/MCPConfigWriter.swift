import Foundation

// MARK: - MCPConfigWriter

/// Persists MCP server definitions by writing them into the opencode server's
/// **global** configuration.
///
/// ## Why not `POST /mcp`
///
/// `POST /mcp` looks like the endpoint for this job and is not. It writes into the
/// instance's in-memory state only — nothing reaches a config file. The server
/// disposes instances on every global config change and on restart, so a server added
/// that way silently disappears.
///
/// ## Why global and not `PATCH /config`
///
/// `PATCH /config` writes `<workspace>/config.json`. The config loader reads
/// `opencode.json` and `opencode.jsonc` from the workspace (walking up) and
/// `.opencode/opencode.json{,c}` — it never reads `<workspace>/config.json`. So that
/// endpoint writes a file nobody loads, and because it also marks the instance for
/// disposal, the change is discarded on the very next request.
///
/// `PATCH /global/config` writes the first existing of
/// `~/.config/opencode/opencode.jsonc`, `opencode.json`, `config.json` — all of which
/// the loader does read. That is the only write path that persists.
///
/// ## Two consequences the UI has to be honest about
///
/// 1. **A successful write disposes every instance on the server**, which interrupts
///    any session that is mid-turn. That is the server's behaviour, not a choice made
///    here.
/// 2. **Keys cannot be removed.** The write is a deep merge, and the config schema
///    accepts neither `null` nor an absent marker for "delete this". Removing a server
///    outright, or dropping a single environment variable, is not expressible over the
///    API — only overwriting or disabling is. `save` reports what it could not remove
///    so the caller can say so out loud.
struct MCPConfigWriter: Sendable {
    let client: APIClient

    private var globalAPI: GlobalAPI { GlobalAPI(client: client) }

    /// The patch body, kept deliberately narrow.
    ///
    /// Encoding a whole `ServerConfig` would put every field the client models into
    /// the request, and the server merges what it receives — so anything the client
    /// round-trips imperfectly would be written back. Sending only `mcp` keeps the
    /// blast radius to the one key being edited.
    private struct McpPatch: Encodable {
        let mcp: [String: McpConfig]
    }

    // MARK: - Result

    struct SaveResult: Sendable {
        /// Environment or header keys the user removed that the server's merge kept.
        /// Non-empty means the config file still contains them.
        var strandedKeys: [String] = []

        var isClean: Bool { strandedKeys.isEmpty }
    }

    // MARK: - Reading

    /// The MCP servers declared in the global config, keyed by name.
    ///
    /// Servers that appear in `GET /mcp` but not here come from a project config file
    /// or from a runtime `POST /mcp`, and cannot be edited through this writer.
    func loadGlobalServers() async throws -> [String: McpConfig] {
        try await globalAPI.config().mcp ?? [:]
    }

    // MARK: - Writing

    /// Write one server definition into the global config.
    ///
    /// - Parameter previous: The entry as it looked before editing, used to detect
    ///   record keys the user dropped — the merge cannot remove them, and the caller
    ///   should surface that rather than let the user believe they are gone.
    @discardableResult
    func save(name: String, config: McpConfig, previous: McpConfig? = nil) async throws -> SaveResult {
        if client.apiVersion == .v2 {
            // 2.x cannot write configuration files over the API; the server is
            // registered with the running instance instead and lasts until it restarts.
            if case .enabledOverride(let enabled) = config {
                try await MCPAPI(client: client).v2Connect(name: name, directory: nil, connect: enabled)
            } else {
                try await MCPAPI(client: client).v2Add(name: name, config: config, directory: nil)
            }
            return SaveResult()
        }
        try await client.requestVoid(.patch("/global/config", body: McpPatch(mcp: [name: config])))
        return SaveResult(strandedKeys: Self.strandedKeys(from: previous, to: config))
    }

    /// Enable or disable a server persistently, preserving the rest of its definition.
    func setEnabled(name: String, config: McpConfig, enabled: Bool) async throws {
        try await save(name: name, config: config.settingEnabled(enabled), previous: config)
    }

    // MARK: - Merge Limits

    /// Record keys present in `previous` but not in `next`.
    ///
    /// `command` is an array and gets replaced wholesale by the merge, so it never
    /// strands. `environment` and `headers` are records and merge key by key.
    static func strandedKeys(from previous: McpConfig?, to next: McpConfig) -> [String] {
        guard let previous else { return [] }

        func dropped(_ before: [String: String]?, _ after: [String: String]?) -> [String] {
            let afterKeys = Set((after ?? [:]).keys)
            return (before ?? [:]).keys.filter { !afterKeys.contains($0) }.sorted()
        }

        switch (previous, next) {
        case (.local(let old), .local(let new)):
            return dropped(old.environment, new.environment)
        case (.remote(let old), .remote(let new)):
            return dropped(old.headers, new.headers)
        default:
            // A type switch replaces the whole entry's shape; the old type's keys
            // remain in the file, but reporting each one would be noise.
            return []
        }
    }
}
