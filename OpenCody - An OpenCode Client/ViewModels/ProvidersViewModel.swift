//
//  ProvidersViewModel.swift
//  OpenCody - An OpenCode Client
//

import Foundation

// MARK: - ProviderEntry

/// A provider joined with everything the screen needs to know about it.
struct ProviderEntry: Identifiable, Sendable {
    let provider: Provider
    let isConnected: Bool
    /// The model ID opencode picks by default for this provider, if any.
    let defaultModelID: String?
    /// Auth methods the server advertises through a plugin. Usually empty: only a
    /// handful of providers have an auth plugin, the rest come from the model catalogue.
    let authMethods: [ProviderAuthMethod]

    var id: String { provider.id }
    var name: String { provider.name }
    var modelCount: Int { provider.models.count }

    /// Whether the app can connect this provider by storing an API key.
    ///
    /// True for effectively everything. Verified against a live server:
    /// `PUT /auth/{providerID}` accepts `{type: "api", key}` for *any* provider ID —
    /// including the ~170 that have no auth plugin at all — and the provider then
    /// reports as connected.
    ///
    /// False only when a provider's auth plugin offers nothing but OAuth flows. The
    /// `connected` list is derived from an auth entry merely existing, so writing a key
    /// for one of those would make it look connected while every request failed. Better
    /// to say it needs a browser login on the server.
    var supportsApiKey: Bool {
        authMethods.isEmpty || authMethods.contains { $0.type == .api }
    }

    /// Where this provider's definition comes from, phrased for humans.
    var sourceLabel: String {
        switch provider.source {
        case .env: return "From environment"
        case .config: return "From config"
        case .custom: return "Custom"
        case .api: return "Built in"
        }
    }

    /// Environment variables that would connect this provider without any UI.
    var envVarHint: String? {
        provider.env.isEmpty ? nil : provider.env.joined(separator: ", ")
    }
}

// MARK: - ProvidersViewModel

/// Loads providers with their auth status and drives connect/disconnect.
///
/// Joins `GET /provider` (list, defaults, connected) with `GET /provider/auth`
/// (available auth methods per provider). The second call is what makes the screen
/// actionable: without it there is no way to know whether a provider can be connected
/// from the app at all, which is why the old read-only screen could only ever say
/// "manage this on your server".
@Observable
@MainActor
final class ProvidersViewModel {

    // MARK: - Observable State

    var entries: [ProviderEntry] = []
    var isLoading = true
    var loadError: String? = nil
    var banner: String? = nil
    var searchText = ""
    /// Provider IDs with an action in flight.
    var pending: Set<String> = []

    // MARK: - Derived

    var connected: [ProviderEntry] { filtered.filter(\.isConnected) }
    var available: [ProviderEntry] { filtered.filter { !$0.isConnected } }

    private var filtered: [ProviderEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || entry.id.localizedCaseInsensitiveContains(query)
                // Searching for a model name is the common way to find its provider.
                || entry.provider.models.values.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let apiClient: APIClient
    @ObservationIgnored private var providerAPI: ProviderAPI { ProviderAPI(client: apiClient) }
    @ObservationIgnored private var globalAPI: GlobalAPI { GlobalAPI(client: apiClient) }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Loading

    func load() async {
        loadError = nil
        defer { isLoading = false }

        async let listTask = providerAPI.list()
        async let methodsTask = providerAPI.allAuthMethods()

        // Auth methods are a bonus; the list is the screen. Await the optional source
        // first so an early return cannot cancel it mid-flight.
        var methods: [String: [ProviderAuthMethod]] = [:]
        do {
            methods = try await methodsTask
        } catch {
            // No plugin methods just means every provider falls back to a plain API
            // key, which still works — so this is not worth surfacing as an error.
            methods = [:]
        }

        let response: ProviderAPI.ProviderListResponse
        do {
            response = try await listTask
        } catch {
            loadError = error.localizedDescription
            entries = []
            return
        }

        let connectedIDs = Set(response.connected)
        entries = response.all
            .map { provider in
                ProviderEntry(
                    provider: provider,
                    isConnected: connectedIDs.contains(provider.id),
                    defaultModelID: response.default[provider.id],
                    authMethods: methods[provider.id] ?? []
                )
            }
            .sorted { lhs, rhs in
                // Connected first, then alphabetical — the useful ones stay at the top.
                if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func entry(id: String) -> ProviderEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - Credentials

    /// Store an API key for a provider.
    func setApiKey(providerID: String, key: String) async throws {
        pending.insert(providerID)
        defer { pending.remove(providerID) }
        try await providerAPI.setApiKey(providerID: providerID, apiKey: key)
        await refreshAfterAuthChange()
    }

    /// Remove stored credentials, disconnecting the provider.
    func disconnect(providerID: String) async {
        pending.insert(providerID)
        defer { pending.remove(providerID) }
        do {
            try await providerAPI.removeCredentials(providerID: providerID)
            await refreshAfterAuthChange()
        } catch {
            banner = error.localizedDescription
            await load()
        }
    }

    // MARK: - Private

    /// Credentials live in a global auth store, but each instance caches the provider
    /// list it resolved from them. Without disposing, a freshly added key does not show
    /// up as connected until the instance happens to be rebuilt.
    private func refreshAfterAuthChange() async {
        try? await globalAPI.disposeInstance()
        await load()
    }
}
