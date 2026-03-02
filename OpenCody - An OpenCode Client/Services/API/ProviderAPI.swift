import Foundation

// MARK: - ProviderAPI

/// Typed wrapper for all provider-related REST endpoints.
///
/// Endpoints:
/// - `GET  /provider`                                    → list all providers
/// - `GET  /provider/{id}/auth`                          → get auth methods
/// - `POST /provider/{id}/auth/{method}`                 → start auth flow
/// - `POST /provider/{id}/auth/{method}/callback`        → complete auth (api-key)
struct ProviderAPI: Sendable {
    let client: APIClient

    // MARK: - Response Types

    /// The `/provider` endpoint returns `{ all: [...], default: {...}, connected: [...] }`.
    struct ProviderListResponse: Codable, Sendable {
        let all: [Provider]
        let `default`: [String: String]
        let connected: [String]
    }


    // MARK: - Request Bodies

    private struct ApiKeyAuthBody: Encodable {
        let apiKey: String
    }

    // MARK: - Endpoints

    /// List all providers with defaults and connected status.
    func list() async throws -> ProviderListResponse {
        let data = try await client.requestData(.get("/provider"))
        return try JSONDecoder().decode(ProviderListResponse.self, from: data)
    }

    /// Get available auth methods for a provider.
    func authMethods(providerID: String) async throws -> [ProviderAuthMethod] {
        let data = try await client.requestData(.get("/provider/\(providerID)/auth"))
        return try JSONDecoder().decode([ProviderAuthMethod].self, from: data)
    }

    /// Start an auth flow for a provider (e.g., OAuth).
    /// Returns the authorization URL and instructions.
    func authorize(providerID: String, method: String) async throws -> ProviderAuthAuthorization {
        let data = try await client.requestData(
            APIEndpoint(path: "/provider/\(providerID)/auth/\(method)", method: .POST)
        )
        return try JSONDecoder().decode(ProviderAuthAuthorization.self, from: data)
    }

    /// Complete API-key auth for a provider.
    func authenticateWithApiKey(providerID: String, method: String, apiKey: String) async throws {
        try await client.requestVoid(
            .post(
                "/provider/\(providerID)/auth/\(method)/callback",
                body: ApiKeyAuthBody(apiKey: apiKey)
            )
        )
    }
}
