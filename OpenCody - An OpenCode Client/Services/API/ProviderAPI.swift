import Foundation

// MARK: - ProviderAPI

/// Typed wrapper for provider listing and authentication endpoints.
///
/// Endpoints:
/// - `GET    /provider`                              → all providers + defaults + connected
/// - `GET    /config/providers`                      → configured providers + default models
/// - `GET    /provider/auth`                         → auth methods, keyed by provider ID
/// - `POST   /provider/{id}/oauth/authorize`         → begin an OAuth flow
/// - `POST   /provider/{id}/oauth/callback`          → complete an OAuth flow
/// - `PUT    /auth/{providerID}`                     → store credentials directly (API key)
/// - `DELETE /auth/{providerID}`                     → remove stored credentials
///
/// Auth methods are addressed by **index** into the array returned by
/// `authMethods(providerID:)` — the server identifies a method by its position,
/// not by name.
struct ProviderAPI: Sendable {
    let client: APIClient

    // MARK: - Response Types

    /// The `/provider` endpoint returns `{ all, default, connected }`.
    struct ProviderListResponse: Codable, Sendable {
        let all: [Provider]
        /// Default model ID per provider ID.
        let `default`: [String: String]
        /// IDs of providers that currently have working credentials.
        let connected: [String]
    }

    // MARK: - Request Bodies

    /// Body of `POST /provider/{id}/oauth/authorize`.
    private struct AuthorizeBody: Encodable {
        /// Index of the auth method in the provider's method list.
        let method: Int
        /// Values collected from the method's `prompts`.
        let inputs: [String: String]?
    }

    /// Body of `POST /provider/{id}/oauth/callback`.
    private struct CallbackBody: Encodable {
        let method: Int
        /// Authorization code pasted or captured from the redirect.
        let code: String?
    }

    // MARK: - Listing

    /// List all providers with defaults and connected status.
    func list(directory: String? = nil) async throws -> ProviderListResponse {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/provider", queryItems: items))
        return try JSONDecoder().decode(ProviderListResponse.self, from: data)
    }

    /// List providers as resolved from configuration, with their default models.
    func listConfigured(directory: String? = nil) async throws -> ConfigProvidersResponse {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/config/providers", queryItems: items))
        return try JSONDecoder().decode(ConfigProvidersResponse.self, from: data)
    }

    // MARK: - Auth Discovery

    /// Get available auth methods for every provider, keyed by provider ID.
    ///
    /// The server exposes this as one call rather than per provider; use
    /// `authMethods(providerID:)` to pull out a single provider's methods.
    func allAuthMethods(directory: String? = nil) async throws -> [String: [ProviderAuthMethod]] {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/provider/auth", queryItems: items))
        return try JSONDecoder().decode([String: [ProviderAuthMethod]].self, from: data)
    }

    /// Get the auth methods for a single provider, in server-defined order.
    ///
    /// The array index is the `method` value passed to `authorize` / `callback`.
    func authMethods(providerID: String, directory: String? = nil) async throws -> [ProviderAuthMethod] {
        let all = try await allAuthMethods(directory: directory)
        return all[providerID] ?? []
    }

    // MARK: - OAuth Flow

    /// Begin an auth flow for a provider.
    ///
    /// - Parameters:
    ///   - providerID: The provider to authenticate.
    ///   - methodIndex: Index into `authMethods(providerID:)`.
    ///   - inputs: Values for the method's `prompts`, keyed by prompt `key`.
    /// - Returns: The URL to open plus how the flow completes — `.auto` finishes on
    ///   its own via a local redirect, `.code` requires calling
    ///   `completeOAuth(providerID:methodIndex:code:)` with a pasted code.
    func authorize(
        providerID: String,
        methodIndex: Int,
        inputs: [String: String]? = nil,
        directory: String? = nil
    ) async throws -> ProviderAuthAuthorization {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let endpoint = APIEndpoint(
            path: "/provider/\(providerID)/oauth/authorize",
            method: .POST,
            body: try JSONEncoder().encode(AuthorizeBody(method: methodIndex, inputs: inputs)),
            queryItems: items
        )
        let data = try await client.requestData(endpoint)
        return try JSONDecoder().decode(ProviderAuthAuthorization.self, from: data)
    }

    /// Complete an OAuth flow with the authorization code from the provider.
    func completeOAuth(
        providerID: String,
        methodIndex: Int,
        code: String?,
        directory: String? = nil
    ) async throws {
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let endpoint = APIEndpoint(
            path: "/provider/\(providerID)/oauth/callback",
            method: .POST,
            body: try JSONEncoder().encode(CallbackBody(method: methodIndex, code: code)),
            queryItems: items
        )
        try await client.requestVoid(endpoint)
    }

    // MARK: - Direct Credentials

    /// Store an API key for a provider.
    ///
    /// This writes the credential straight into the server's auth store via
    /// `PUT /auth/{providerID}`, bypassing the OAuth flow. It is the right call for
    /// providers whose auth method is `.api`.
    func setApiKey(providerID: String, apiKey: String, metadata: [String: String]? = nil) async throws {
        let credential = ProviderCredential.api(key: apiKey, metadata: metadata)
        try await client.requestVoid(.put("/auth/\(providerID)", body: credential))
    }

    /// Store an OAuth credential set for a provider.
    func setOAuthCredential(
        providerID: String,
        access: String,
        refresh: String,
        expires: Int
    ) async throws {
        let credential = ProviderCredential.oauth(access: access, refresh: refresh, expires: expires)
        try await client.requestVoid(.put("/auth/\(providerID)", body: credential))
    }

    /// Remove stored credentials for a provider (disconnect it).
    func removeCredentials(providerID: String) async throws {
        try await client.requestVoid(.delete("/auth/\(providerID)"))
    }
}
