import Foundation

// MARK: - MCPAPI

/// Typed wrapper for all MCP (Model Context Protocol) related REST endpoints.
///
/// Endpoints:
/// - `GET  /mcp`                  → list all MCP servers with status
/// - `POST /mcp/{name}/connect`   → connect an MCP server
/// - `POST /mcp/{name}/disconnect`→ disconnect an MCP server
/// - `POST /mcp`                  → add a new MCP server
/// - `DELETE /mcp/{name}`         → remove an MCP server
/// - `GET  /lsp`                  → list LSP servers
/// - `GET  /formatter`            → list formatters
struct MCPAPI: Sendable {
    let client: APIClient

    // MARK: - Response Types

    /// The `/mcp` GET endpoint returns a dictionary of server name → status.
    typealias McpStatusMap = [String: McpStatus]

    // MARK: - Request Bodies

    private struct McpAddBody: Encodable {
        let name: String
        let config: McpConfig
    }

    // MARK: - Endpoints

    /// List all MCP servers and their statuses.
    func list() async throws -> McpStatusMap {
        let data = try await client.requestData(.get("/mcp"))
        return try JSONDecoder().decode(McpStatusMap.self, from: data)
    }

    /// Connect (or reconnect) an MCP server.
    func connect(name: String) async throws {
        try await client.requestVoid(
            APIEndpoint(path: "/mcp/\(name)/connect", method: .POST)
        )
    }

    /// Disconnect an MCP server.
    func disconnect(name: String) async throws {
        try await client.requestVoid(
            APIEndpoint(path: "/mcp/\(name)/disconnect", method: .POST)
        )
    }

    /// Add a new MCP server configuration.
    func add(name: String, config: McpConfig) async throws {
        try await client.requestVoid(
            .post("/mcp", body: McpAddBody(name: name, config: config))
        )
    }

    /// Remove an MCP server.
    func remove(name: String) async throws {
        try await client.requestVoid(.delete("/mcp/\(name)"))
    }

    /// List all LSP servers and their statuses.
    func listLsp() async throws -> [LspStatus] {
        let data = try await client.requestData(.get("/lsp"))
        return try JSONDecoder().decode([LspStatus].self, from: data)
    }

    /// List all formatters.
    func listFormatters() async throws -> [FormatterStatus] {
        let data = try await client.requestData(.get("/formatter"))
        return try JSONDecoder().decode([FormatterStatus].self, from: data)
    }
}
