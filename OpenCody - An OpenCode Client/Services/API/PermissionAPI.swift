import Foundation

// MARK: - PermissionAPI

/// Typed wrapper for permission-request endpoints.
///
/// Endpoints:
/// - `GET  /permission`                      → list pending permission requests (v1)
/// - `POST /permission/{requestID}/reply`    → reply to a request (v1)
/// - `GET  /api/permission/request`          → list pending requests (v2)
/// - `POST /api/session/{sessionID}/permission/{requestID}/reply` → reply (v2)
/// - `GET  /api/permission/saved`            → list persisted "always" decisions
/// - `DELETE /api/permission/saved/{id}`     → revoke a persisted decision
///
/// The v1 route is the primary surface. `reply(to:decision:)` picks the route from
/// the request's `variant` and falls back to the deprecated per-session route when
/// the server predates the dedicated permission endpoints.
struct PermissionAPI: Sendable {
    let client: APIClient

    // MARK: - Request Bodies

    private struct ReplyBody: Encodable {
        let reply: String
        let message: String?
    }

    /// Body of the deprecated `POST /session/{sessionID}/permissions/{permissionID}` route.
    private struct LegacyReplyBody: Encodable {
        let response: String
    }

    // MARK: - Listing

    /// List pending v1 permission requests.
    /// - Parameter directory: Optional project directory scope.
    func list(directory: String? = nil) async throws -> [Permission] {
        if client.apiVersion == .v2 { return try await v2List(directory: directory) }
        let items = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/permission", queryItems: items))
        return try JSONDecoder().decode([Permission].self, from: data)
    }

    /// List pending v2 permission requests.
    ///
    /// The v2 surface wraps its payload in `{ location, data }`.
    func listV2(directory: String? = nil, workspace: String? = nil) async throws -> [Permission] {
        var items: [URLQueryItem] = []
        if let directory { items.append(URLQueryItem(name: "location[directory]", value: directory)) }
        if let workspace { items.append(URLQueryItem(name: "location[workspace]", value: workspace)) }
        let data = try await client.requestData(
            .get("/api/permission/request", queryItems: items.isEmpty ? nil : items)
        )
        return try JSONDecoder().decode(V2Envelope<[Permission]>.self, from: data).data
    }

    /// List pending permission requests across both API generations.
    ///
    /// A server may implement only one of the two surfaces, so a failure on either
    /// side is not fatal — whatever the other returns is still used.
    func listAll(directory: String? = nil) async throws -> [Permission] {
        if client.apiVersion == .v2 { return try await v2List(directory: directory) }
        let v1 = try? await list(directory: directory)
        let v2 = try? await listV2(directory: directory)
        if v1 == nil, v2 == nil {
            // Surface the v1 error rather than silently returning nothing.
            return try await list(directory: directory)
        }
        return (v1 ?? []) + (v2 ?? [])
    }

    // MARK: - Replying

    /// Reply to a pending permission request.
    ///
    /// - Parameters:
    ///   - permission: The request being answered — its `variant` selects the route.
    ///   - decision: `.once`, `.always`, or `.reject`.
    ///   - message: Optional note passed back to the assistant (usually a denial reason).
    func reply(
        to permission: Permission,
        decision: PermissionReplyDecision,
        message: String? = nil
    ) async throws {
        if client.apiVersion == .v2 {
            return try await v2Reply(to: permission, decision: decision, message: message)
        }
        let body = ReplyBody(reply: decision.rawValue, message: message)

        let path: String
        switch permission.variant {
        case .v1:
            path = "/permission/\(permission.id)/reply"
        case .v2:
            path = "/api/session/\(permission.sessionID)/permission/\(permission.id)/reply"
        }

        do {
            try await client.requestVoid(.post(path, body: body))
        } catch OpenCodeError.notFound {
            // Server predates the dedicated permission routes — fall back to the
            // deprecated per-session endpoint, which takes `{ response }`.
            try await replyLegacy(
                sessionID: permission.sessionID,
                permissionID: permission.id,
                decision: decision
            )
        }
    }

    /// Reply via the deprecated `POST /session/{sessionID}/permissions/{permissionID}` route.
    func replyLegacy(
        sessionID: String,
        permissionID: String,
        decision: PermissionReplyDecision
    ) async throws {
        try await client.requestVoid(
            .post(
                "/session/\(sessionID)/permissions/\(permissionID)",
                body: LegacyReplyBody(response: decision.rawValue)
            )
        )
    }

    // MARK: - Saved Decisions

    /// List persisted "always allow" decisions, optionally scoped to one project.
    func listSaved(projectID: String? = nil) async throws -> [PermissionSavedInfo] {
        let items = projectID.map { [URLQueryItem(name: "projectID", value: $0)] }
        let data = try await client.requestData(.get("/api/permission/saved", queryItems: items))
        return try JSONDecoder().decode(V2Envelope<[PermissionSavedInfo]>.self, from: data).data
    }

    /// Revoke a persisted "always allow" decision.
    func removeSaved(id: String) async throws {
        try await client.requestVoid(.delete("/api/permission/saved/\(id)"))
    }
}
