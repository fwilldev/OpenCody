import Foundation

// MARK: - GlobalAPI

/// Typed wrapper for server-wide (non project-scoped) endpoints.
///
/// Endpoints:
/// - `GET   /global/health`   → health + server version
/// - `GET   /global/config`   → global configuration
/// - `PATCH /global/config`   → update global configuration
/// - `POST  /global/upgrade`  → upgrade the opencode installation
/// - `POST  /global/dispose`  → dispose all instances
/// - `POST  /instance/dispose`→ dispose the instance for one directory
struct GlobalAPI: Sendable {
    let client: APIClient

    private struct UpgradeBody: Encodable {
        let target: String?
    }

    // MARK: - Health

    /// Get health status and the running server version.
    ///
    /// Preferred over `APIClient.healthCheck()` when the version matters — e.g. to
    /// decide whether an endpoint the client wants is available.
    func health() async throws -> HealthInfo {
        let data = try await client.requestData(.get("/global/health"))
        return try JSONDecoder().decode(HealthInfo.self, from: data)
    }

    // MARK: - Configuration

    /// Get the global (non project-scoped) configuration.
    func config() async throws -> ServerConfig {
        let data = try await client.requestData(.get("/global/config"))
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }

    /// Partially update the global configuration.
    func updateConfig(_ config: ServerConfig) async throws -> ServerConfig {
        let data = try await client.requestData(.patch("/global/config", body: config))
        return try JSONDecoder().decode(ServerConfig.self, from: data)
    }

    // MARK: - Lifecycle

    /// Upgrade opencode.
    /// - Parameter target: Specific version to install, or `nil` for the latest.
    func upgrade(target: String? = nil) async throws -> UpgradeResult {
        let endpoint = APIEndpoint(
            path: "/global/upgrade",
            method: .POST,
            body: try JSONEncoder().encode(UpgradeBody(target: target)),
            // An upgrade downloads and swaps the binary — allow generous time.
            timeoutOverride: 600
        )
        let data = try await client.requestData(endpoint)
        return try JSONDecoder().decode(UpgradeResult.self, from: data)
    }

    /// Dispose every opencode instance, releasing all resources.
    func disposeAll() async throws {
        try await client.requestVoid(APIEndpoint(path: "/global/dispose", method: .POST))
    }

    /// Dispose the instance serving one project directory.
    func disposeInstance(directory: String? = nil) async throws {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        try await client.requestVoid(
            APIEndpoint(path: "/instance/dispose", method: .POST, queryItems: items)
        )
    }
}
