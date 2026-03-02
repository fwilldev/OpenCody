import Foundation

// MARK: - ConfigAPI

/// Typed wrapper for all config-related REST endpoints.
///
/// Endpoints:
/// - `GET   /config`   → get current config
/// - `PATCH /config`   → update config
struct ConfigAPI: Sendable {
    let client: APIClient

    // MARK: - Endpoints

    /// Get the current server configuration.
    func get() async throws -> ServerConfig {
        let data = try await client.requestData(.get("/config"))
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }

    /// Partially update the server configuration.
    /// Only the fields set on `config` are sent; all fields are optional.
    func update(_ config: ServerConfig) async throws -> ServerConfig {
        let data = try await client.requestData(.patch("/config", body: config))
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }
}
