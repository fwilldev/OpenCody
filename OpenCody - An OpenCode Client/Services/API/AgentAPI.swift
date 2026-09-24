import Foundation

// MARK: - AgentAPI

/// Typed wrapper for all agent-related REST endpoints.
///
/// Endpoints:
/// - `GET /agent` → list all agents
struct AgentAPI: Sendable {
    let client: APIClient

    // MARK: - Endpoints

    /// List all available agents.
    func list() async throws -> [Agent] {
        if client.apiVersion == .v2 { return try await v2List() }
        let data = try await client.requestData(.get("/agent"))
        return try JSONDecoder().decode([Agent].self, from: data)
    }
}
