import Foundation

// MARK: - CommandAPI

/// Typed wrapper for command, tool, and skill endpoints.
///
/// Endpoints:
/// - `GET  /command`                        → list slash commands
/// - `POST /session/{sessionID}/command`    → execute a slash command
/// - `GET  /skill`                          → list agent skills
/// - `GET  /experimental/tool`              → list tools with JSON-schema parameters
/// - `GET  /experimental/tool/ids`          → list tool IDs only
struct CommandAPI: Sendable {
    let client: APIClient

    // MARK: - Request Bodies

    /// Body of `POST /session/{sessionID}/command`.
    ///
    /// The command name is sent as `command` — **not** `name` — and both `command`
    /// and `arguments` are required by the server, so `arguments` is sent as an
    /// empty string when the user supplied none.
    private struct ExecuteBody: Encodable {
        let command: String
        let arguments: String
        let messageID: String?
        let agent: String?
        let model: String?
        let variant: String?
    }

    // MARK: - Commands

    /// List all available slash commands.
    func list(directory: String? = nil) async throws -> [SlashCommand] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/command", queryItems: items))
        return try JSONDecoder().decode([SlashCommand].self, from: data)
    }

    /// Execute a slash command in a session.
    ///
    /// - Parameters:
    ///   - sessionID: The session to execute the command in.
    ///   - command: The command name (without the leading `/`).
    ///   - arguments: Arguments string; empty when the command takes none.
    ///   - messageID: Optional client-chosen ID for the resulting message.
    ///   - agent: Override the agent the command runs as.
    ///   - model: Override the model, as a `providerID/modelID` string.
    ///   - variant: Optional model variant (e.g. a reasoning-effort tier).
    func execute(
        sessionID: String,
        command: String,
        arguments: String = "",
        messageID: String? = nil,
        agent: String? = nil,
        model: String? = nil,
        variant: String? = nil
    ) async throws {
        let body = ExecuteBody(
            command: command,
            arguments: arguments,
            messageID: messageID,
            agent: agent,
            model: model,
            variant: variant
        )
        // The server streams the assistant reply; the response body is discarded
        // here because the UI consumes it through SSE.
        try await client.requestVoid(
            APIEndpoint(
                path: "/session/\(sessionID)/command",
                method: .POST,
                body: try JSONEncoder().encode(body),
                timeoutOverride: 300
            )
        )
    }

    // MARK: - Skills

    /// List all agent skills registered on the server.
    func listSkills(directory: String? = nil) async throws -> [Skill] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/skill", queryItems: items))
        return try JSONDecoder().decode([Skill].self, from: data)
    }

    // MARK: - Tools

    /// List available tools with their JSON-schema parameters.
    ///
    /// The server resolves the tool set per provider/model pair, so both are required.
    func listTools(
        providerID: String,
        modelID: String,
        directory: String? = nil
    ) async throws -> [ToolListItem] {
        var items = [
            URLQueryItem(name: "provider", value: providerID),
            URLQueryItem(name: "model", value: modelID),
        ]
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        let data = try await client.requestData(.get("/experimental/tool", queryItems: items))
        return try JSONDecoder().decode([ToolListItem].self, from: data)
    }

    /// List all tool IDs — built-in plus dynamically registered (MCP) tools.
    ///
    /// Unlike `listTools`, this needs no provider/model and is the cheap way to
    /// discover which tools exist.
    func listToolIDs(directory: String? = nil) async throws -> [String] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/experimental/tool/ids", queryItems: items))
        return try JSONDecoder().decode([String].self, from: data)
    }
}
