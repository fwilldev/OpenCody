import Foundation

// MARK: - CommandAPI

/// Typed wrapper for all command/tool-related REST endpoints.
///
/// Endpoints:
/// - `GET  /command`          → list slash commands
/// - `POST /command/execute`  → execute a slash command
/// - `GET  /tool`             → list available tools
struct CommandAPI: Sendable {
    let client: APIClient

    // MARK: - Request Bodies

    private struct ExecuteBody: Encodable {
        let sessionID: String
        let name: String
        let arguments: String
    }

    // MARK: - Endpoints

    /// List all available slash commands.
    func list() async throws -> [SlashCommand] {
        let data = try await client.requestData(.get("/command"))
        return try JSONDecoder().decode([SlashCommand].self, from: data)
    }

    /// Execute a slash command in a session.
    func execute(sessionID: String, name: String, arguments: String = "") async throws {
        try await client.requestVoid(
            .post("/command/execute", body: ExecuteBody(sessionID: sessionID, name: name, arguments: arguments))
        )
    }

    /// List all available tools.
    func listTools() async throws -> [ToolListItem] {
        let data = try await client.requestData(.get("/tool"))
        return try JSONDecoder().decode([ToolListItem].self, from: data)
    }
}
