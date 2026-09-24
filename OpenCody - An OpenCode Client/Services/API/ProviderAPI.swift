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
        if client.apiVersion == .v2 { return try await v2List(directory: directory) }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/provider", queryItems: items))
        return try JSONDecoder().decode(ProviderListResponse.self, from: data)
    }

    /// List providers as resolved from configuration, with their default models.
    func listConfigured(directory: String? = nil) async throws -> ConfigProvidersResponse {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Configured provider listing") }
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
        if client.apiVersion == .v2 { return try await v2AllAuthMethods(directory: directory) }
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

    // The two calls below are kept so this wrapper still mirrors the server's auth
    // surface, but **the app deliberately does not use them**. Driving a provider's
    // browser sign-in in-app means signing a user into a subscription bought outside
    // the app, which App Review can read as access to externally purchased content.
    // OpenCody connects providers with an API key only (`setApiKey`); anyone who needs
    // an OAuth provider runs `opencode auth login` on the server and the credential
    // lands in the same store. See `ProviderAuthSheet`.

    /// Begin an auth flow for a provider.
    ///
    /// - Parameters:
    ///   - providerID: The provider to authenticate.
    ///   - methodIndex: Index into `authMethods(providerID:)`.
    ///   - inputs: Values for the method's `prompts`, keyed by prompt `key`.
    /// - Returns: The URL to open plus how the flow completes — `.auto` finishes on
    ///   its own via a local redirect, `.code` requires calling
    ///   `completeOAuth(providerID:methodIndex:code:)` with a pasted code.
    ///
    ///   `nil` when the chosen method is not an OAuth method: the server answers with
    ///   JSON `null` and does nothing. Store the credential with `setApiKey` instead.
    ///
    /// - Important: `authorize` parks per-instance state that `completeOAuth` then
    ///   looks up, so both calls must pass the same `directory`.
    func authorize(
        providerID: String,
        methodIndex: Int,
        inputs: [String: String]? = nil,
        directory: String? = nil
    ) async throws -> ProviderAuthAuthorization? {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("In-app provider sign-in") }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let endpoint = APIEndpoint(
            path: "/provider/\(APIEndpoint.segment(providerID))/oauth/authorize",
            method: .POST,
            body: try JSONEncoder().encode(AuthorizeBody(method: methodIndex, inputs: inputs)),
            queryItems: items
        )
        let data = try await client.requestData(endpoint)
        if data.isEmpty { return nil }
        let decoder = JSONDecoder()
        // The route serializes a missing result as literal `null` rather than an empty
        // body, so decode through an optional instead of failing.
        return try decoder.decode(ProviderAuthAuthorization?.self, from: data)
    }

    /// Complete an OAuth flow with the authorization code from the provider.
    func completeOAuth(
        providerID: String,
        methodIndex: Int,
        code: String?,
        directory: String? = nil
    ) async throws {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("In-app provider sign-in") }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let endpoint = APIEndpoint(
            path: "/provider/\(APIEndpoint.segment(providerID))/oauth/callback",
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
    /// providers whose auth method is `.api` — for those, `authorize` deliberately
    /// does nothing and returns `nil`.
    ///
    /// The auth store is global, but each instance caches its resolved provider list,
    /// so dispose the instance afterwards for the change to show up.
    func setApiKey(providerID: String, apiKey: String, metadata: [String: String]? = nil) async throws {
        if client.apiVersion == .v2 { return try await v2SetApiKey(providerID: providerID, apiKey: apiKey) }
        let credential = ProviderCredential.api(key: apiKey, metadata: metadata)
        try await client.requestVoid(.put("/auth/\(APIEndpoint.segment(providerID))", body: credential))
    }

    /// Store an OAuth credential set for a provider.
    func setOAuthCredential(
        providerID: String,
        access: String,
        refresh: String,
        expires: Int
    ) async throws {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Storing OAuth credentials") }
        let credential = ProviderCredential.oauth(access: access, refresh: refresh, expires: expires)
        try await client.requestVoid(.put("/auth/\(APIEndpoint.segment(providerID))", body: credential))
    }

    /// Remove stored credentials for a provider (disconnect it).
    func removeCredentials(providerID: String) async throws {
        if client.apiVersion == .v2 { return try await v2RemoveCredentials(providerID: providerID) }
        try await client.requestVoid(.delete("/auth/\(APIEndpoint.segment(providerID))"))
    }
}
