import Foundation

// MARK: - CommandAPI

/// Typed wrapper for all command/tool-related REST endpoints.
///
/// Endpoints:
/// - `GET  /command`                        → list slash commands
/// - `POST /session/:sessionID/command`     → execute a slash command
/// - `GET  /tool`                           → list available tools
struct CommandAPI: Sendable {
    let client: APIClient

    // MARK: - Request Bodies

    private struct ExecuteBody: Encodable {
        let name: String
        let arguments: String?
        let messageID: String?
    }

    // MARK: - Endpoints

    /// List all available slash commands.
    func list() async throws -> [SlashCommand] {
        let data = try await client.requestData(.get("/command"))
        return try JSONDecoder().decode([SlashCommand].self, from: data)
    }

    /// Execute a slash command in a session.
    /// - Parameters:
    ///   - sessionID: The session to execute the command in.
    ///   - name: The command name (without leading "/").
    ///   - arguments: Optional arguments string.
    ///   - messageID: Optional message ID context.
    func execute(sessionID: String, name: String, arguments: String? = nil, messageID: String? = nil) async throws {
        try await client.requestVoid(
            .post("/session/\(sessionID)/command", body: ExecuteBody(name: name, arguments: arguments, messageID: messageID))
        )
    }

    /// List all available tools.
    func listTools() async throws -> [ToolListItem] {
        let data = try await client.requestData(.get("/tool"))
        return try JSONDecoder().decode([ToolListItem].self, from: data)
    }
}
