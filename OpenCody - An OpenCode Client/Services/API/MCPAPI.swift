import Foundation

// MARK: - MCPAPI

/// Typed wrapper for MCP (Model Context Protocol), LSP, and formatter endpoints.
///
/// Endpoints:
/// - `GET    /mcp`                            → all MCP servers with status
/// - `POST   /mcp`                            → add a server
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
/// There is no endpoint to delete an MCP server: servers come from configuration.
/// To stop using one, `disconnect` it, or disable it in the config file.
struct MCPAPI: Sendable {
    let client: APIClient

    // MARK: - Response Types

    /// The `/mcp` GET endpoint returns a dictionary of server name → status.
    typealias McpStatusMap = [String: McpStatus]

    /// Result of starting an MCP OAuth flow.
    struct McpOAuthStart: Decodable, Sendable {
        let authorizationUrl: String
        /// Opaque state string to echo back; the server also retains it.
        let oauthState: String
    }

    // MARK: - Request Bodies

    private struct McpAddBody: Encodable {
        let name: String
        let config: McpConfig
    }

    private struct McpAuthCallbackBody: Encodable {
        let code: String
    }

    // MARK: - Servers

    /// List all MCP servers and their statuses.
    func list(directory: String? = nil) async throws -> McpStatusMap {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/mcp", queryItems: items))
        return try JSONDecoder().decode(McpStatusMap.self, from: data)
    }

    /// Add a new MCP server configuration at runtime.
    /// - Returns: The refreshed status map, including the new server.
    @discardableResult
    func add(name: String, config: McpConfig) async throws -> McpStatusMap {
        let data = try await client.requestData(.post("/mcp", body: McpAddBody(name: name, config: config)))
        return (try? JSONDecoder().decode(McpStatusMap.self, from: data)) ?? [:]
    }

    /// Connect (or reconnect) an MCP server.
    func connect(name: String) async throws {
        try await client.requestVoid(APIEndpoint(path: "/mcp/\(name)/connect", method: .POST))
    }

    /// Disconnect an MCP server.
    func disconnect(name: String) async throws {
        try await client.requestVoid(APIEndpoint(path: "/mcp/\(name)/disconnect", method: .POST))
    }

    // MARK: - OAuth

    /// Begin an OAuth flow for an MCP server that reports `needs_auth`.
    ///
    /// Open the returned `authorizationUrl`, then pass the resulting code to
    /// `completeOAuth(name:code:)`.
    func startOAuth(name: String) async throws -> McpOAuthStart {
        let data = try await client.requestData(APIEndpoint(path: "/mcp/\(name)/auth", method: .POST))
        return try JSONDecoder().decode(McpOAuthStart.self, from: data)
    }

    /// Complete an MCP OAuth flow with the authorization code.
    /// - Returns: The server's new status.
    @discardableResult
    func completeOAuth(name: String, code: String) async throws -> McpStatus {
        let data = try await client.requestData(
            .post("/mcp/\(name)/auth/callback", body: McpAuthCallbackBody(code: code))
        )
        return try JSONDecoder().decode(McpStatus.self, from: data)
    }

    /// Run the whole OAuth flow server-side, which opens a browser on the **host**
    /// machine and blocks until the callback arrives.
    ///
    /// Only useful when the client and server share a desktop. Prefer
    /// `startOAuth` + `completeOAuth` from iOS.
    @discardableResult
    func authenticate(name: String) async throws -> McpStatus {
        let data = try await client.requestData(
            APIEndpoint(path: "/mcp/\(name)/auth/authenticate", method: .POST, timeoutOverride: 300)
        )
        return try JSONDecoder().decode(McpStatus.self, from: data)
    }

    /// Remove stored OAuth credentials for an MCP server, forcing re-authentication.
    func removeOAuth(name: String) async throws {
        try await client.requestVoid(.delete("/mcp/\(name)/auth"))
    }

    // MARK: - Resources

    /// Get all resources advertised by connected MCP servers, keyed by resource name.
    func resources(directory: String? = nil) async throws -> [String: McpResource] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/experimental/resource", queryItems: items))
        return try JSONDecoder().decode([String: McpResource].self, from: data)
    }

    // MARK: - LSP & Formatters

    /// List all LSP servers and their statuses.
    func listLsp(directory: String? = nil) async throws -> [LspStatus] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/lsp", queryItems: items))
        return try JSONDecoder().decode([LspStatus].self, from: data)
    }

    /// List all formatters and whether they are enabled.
    func listFormatters(directory: String? = nil) async throws -> [FormatterStatus] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/formatter", queryItems: items))
        return try JSONDecoder().decode([FormatterStatus].self, from: data)
    }
}
