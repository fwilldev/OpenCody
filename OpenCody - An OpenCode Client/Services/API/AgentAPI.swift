import Foundation

// MARK: - AgentAPI

/// Typed wrapper for all agent-related REST endpoints.
///
/// Endpoints:
/// - `GET /agent` → list all agents
struct AgentAPI: Sendable {
    let client: APIClient

    // MARK: - Endpoints

    /// List the agents available in a project (`nil`: the server's own directory).
    func list(directory: String? = nil) async throws -> [Agent] {
        if client.apiVersion == .v2 { return try await v2List(directory: directory) }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/agent", queryItems: items))
        return try JSONDecoder().decode([Agent].self, from: data)
    }
}
