import Foundation

// MARK: - MCPAPI

/// Typed wrapper for MCP (Model Context Protocol), LSP, and formatter endpoints.
///
/// Endpoints:
/// - `GET    /mcp`                            → all MCP servers with status
/// - `POST   /mcp`                            → add a server **for this instance only**
/// - `POST   /mcp/{name}/connect`             → connect a server
/// - `POST   /mcp/{name}/disconnect`          → disconnect a server
/// - `POST   /mcp/{name}/auth`                → begin OAuth, returns an authorize URL
/// - `POST   /mcp/{name}/auth/callback`       → complete OAuth with a code
/// - `POST   /mcp/{name}/auth/authenticate`   → server-driven OAuth (opens a browser host-side)
/// - `DELETE /mcp/{name}/auth`                → remove stored OAuth credentials
/// - `GET    /experimental/resource`          → MCP resources from connected servers
/// - `GET    /lsp`                            → LSP server status
/// - `GET    /formatter`                      → formatter status
///
/// ## Two things worth knowing before using this
///
/// **Every MCP route is instance-scoped.** They all sit behind the server's workspace
/// routing middleware, so a call without a `directory` lands on the instance for the
/// server's own working directory — which resolves a different config chain, and
/// therefore a different set of MCP servers. Pass `directory` whenever the caller
/// knows one.
///
/// **`add` does not persist.** It writes into the instance's in-memory state and
/// never touches a config file, so a server added this way is gone the next time the
/// instance is disposed — which the server does on every global config change, and on
/// restart. For a server that should stick, write it to the config instead
/// (`MCPConfigWriter`); this method is only for a deliberately throwaway server.
///
/// There is no endpoint to delete an MCP server — servers come from configuration.
struct MCPAPI: Sendable {
    let client: APIClient

    // MARK: - Response Types

    /// The `/mcp` GET endpoint returns a dictionary of server name → status.
    typealias McpStatusMap = [String: McpStatus]

    /// Result of starting an MCP OAuth flow.
    struct McpOAuthStart: Decodable, Sendable {
        /// The URL the user must authorize at.
        ///
        /// Empty when the server turned out to be authorized already — in that case
        /// there is nothing to open, just reconnect.
        let authorizationUrl: String
        /// Opaque state string to echo back; the server also retains it.
        let oauthState: String

        var needsAuthorization: Bool { !authorizationUrl.isEmpty }
    }

    // MARK: - Request Bodies

    private struct McpAddBody: Encodable {
        let name: String
        let config: McpConfig
    }

    private struct McpAuthCallbackBody: Encodable {
        let code: String
    }

    // MARK: - Helpers

    private func query(_ directory: String?) -> [URLQueryItem]? {
        directory.map { [URLQueryItem(name: "directory", value: $0)] }
    }

    /// Build a `/mcp/{name}/…` path with the name safely encoded.
    private func serverPath(_ name: String, _ suffix: String = "") -> String {
        "/mcp/\(APIEndpoint.segment(name))\(suffix)"
    }

    // MARK: - Servers

    /// List all MCP servers and their statuses.
    func list(directory: String? = nil) async throws -> McpStatusMap {
        if client.apiVersion == .v2 { return try await v2List(directory: directory) }
        let data = try await client.requestData(.get("/mcp", queryItems: query(directory)))
        return try JSONDecoder().decode(McpStatusMap.self, from: data)
    }

    /// Add an MCP server to the running instance **without persisting it**.
    ///
    /// See the type-level note: this is deliberately ephemeral. Use
    /// `MCPConfigWriter.save` for a server the user expects to find again later.
    /// - Returns: The refreshed status map, including the new server.
    @discardableResult
    func add(name: String, config: McpConfig, directory: String? = nil) async throws -> McpStatusMap {
        if client.apiVersion == .v2 { return try await v2Add(name: name, config: config, directory: directory) }
        let data = try await client.requestData(
            .post("/mcp", body: McpAddBody(name: name, config: config), queryItems: query(directory))
        )
        return try JSONDecoder().decode(McpStatusMap.self, from: data)
    }

    /// Connect (or reconnect) an MCP server.
    func connect(name: String, directory: String? = nil) async throws {
        if client.apiVersion == .v2 { return try await v2Connect(name: name, directory: directory, connect: true) }
        try await client.requestVoid(.post(serverPath(name, "/connect"), queryItems: query(directory)))
    }

    /// Disconnect an MCP server.
    func disconnect(name: String, directory: String? = nil) async throws {
        if client.apiVersion == .v2 { return try await v2Connect(name: name, directory: directory, connect: false) }
        try await client.requestVoid(.post(serverPath(name, "/disconnect"), queryItems: query(directory)))
    }

    // MARK: - OAuth

    // These are kept so the wrapper still mirrors the server's MCP surface, but **the
    // app does not use them**, for the same reason it does not drive provider OAuth:
    // an in-app browser sign-in into a third-party account is what App Review reads as
    // access to externally purchased content. There is a second, practical reason here
    // too — the server's redirect URI is `http://127.0.0.1:19876/mcp/oauth/callback` on
    // the *server host*, which a phone talking to a remote server cannot reach, so the
    // code would have to be intercepted or pasted by hand.
    //
    // A remote MCP server that needs authentication is configured with a bearer token
    // under `headers`, or authenticated on the server itself. `MCPView` says so instead
    // of offering a Connect button that can only ever return `needs_auth` again.

    /// Begin an OAuth flow for an MCP server that reports `needs_auth`.
    ///
    /// Open the returned `authorizationUrl`, then pass the resulting code to
    /// `completeOAuth(name:code:)`. Both calls must use the same `directory`, since
    /// the server resolves the MCP config per instance.
    ///
    /// Only remote servers with OAuth enabled support this; the server rejects
    /// anything else with a 400.
    func startOAuth(name: String, directory: String? = nil) async throws -> McpOAuthStart {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("MCP sign-in") }
        let data = try await client.requestData(
            .post(serverPath(name, "/auth"), queryItems: query(directory))
        )
        return try JSONDecoder().decode(McpOAuthStart.self, from: data)
    }

    /// Complete an MCP OAuth flow with the authorization code.
    /// - Returns: The server's new status.
    @discardableResult
    func completeOAuth(name: String, code: String, directory: String? = nil) async throws -> McpStatus {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("MCP sign-in") }
        let data = try await client.requestData(
            .post(serverPath(name, "/auth/callback"), body: McpAuthCallbackBody(code: code), queryItems: query(directory))
        )
        return try JSONDecoder().decode(McpStatus.self, from: data)
    }

    /// Run the whole OAuth flow server-side, which opens a browser on the **host**
    /// machine and blocks until the callback arrives.
    ///
    /// Only useful when the client and server share a desktop. Prefer
    /// `startOAuth` + `completeOAuth` from iOS.
    @discardableResult
    func authenticate(name: String, directory: String? = nil) async throws -> McpStatus {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("MCP sign-in") }
        let data = try await client.requestData(
            APIEndpoint(
                path: serverPath(name, "/auth/authenticate"),
                method: .POST,
                queryItems: query(directory),
                timeoutOverride: 300,
                contentType: .none
            )
        )
        return try JSONDecoder().decode(McpStatus.self, from: data)
    }

    /// Remove stored OAuth credentials for an MCP server, forcing re-authentication.
    func removeOAuth(name: String, directory: String? = nil) async throws {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("MCP sign-in") }
        try await client.requestVoid(.delete(serverPath(name, "/auth"), queryItems: query(directory)))
    }

    // MARK: - Resources

    /// Get all resources advertised by connected MCP servers, keyed by resource name.
    func resources(directory: String? = nil) async throws -> [String: McpResource] {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("MCP resource listing") }
        let data = try await client.requestData(.get("/experimental/resource", queryItems: query(directory)))
        return try JSONDecoder().decode([String: McpResource].self, from: data)
    }

    // MARK: - LSP & Formatters

    /// List all LSP servers and their statuses.
    func listLsp(directory: String? = nil) async throws -> [LspStatus] {
        if client.apiVersion == .v2 { return [] }
        let data = try await client.requestData(.get("/lsp", queryItems: query(directory)))
        return try JSONDecoder().decode([LspStatus].self, from: data)
    }

    /// List all formatters and whether they are enabled.
    func listFormatters(directory: String? = nil) async throws -> [FormatterStatus] {
        if client.apiVersion == .v2 { return [] }
        let data = try await client.requestData(.get("/formatter", queryItems: query(directory)))
        return try JSONDecoder().decode([FormatterStatus].self, from: data)
    }
}
