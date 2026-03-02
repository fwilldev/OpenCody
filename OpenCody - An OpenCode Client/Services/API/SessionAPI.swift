import Foundation

// MARK: - SessionAPI

/// Typed wrapper for all session-related REST endpoints.
///
/// Endpoints:
/// - `GET    /session`               → list all sessions
/// - `POST   /session`               → create a new session
/// - `GET    /session/{id}`           → get one session
/// - `DELETE /session/{id}`           → delete a session
/// - `POST   /session/{id}/abort`     → abort a running session
/// - `POST   /session/{id}/summarize` → summarize a session
/// - `POST   /session/{id}/share`     → share a session
/// - `DELETE /session/{id}/share`     → unshare a session
/// - `POST   /session/{id}/fork`      → fork a session
/// - `POST   /session/{id}/init`      → initialize a session
/// - `POST   /session/{id}/revert`    → revert a session
/// - `POST   /session/{id}/unrevert`  → undo a revert
/// - `GET    /session/{id}/diff`      → get session diffs
/// - `GET    /session/status`         → get status of all sessions
/// - `POST   /session/{id}/permissions/{permissionID}` → reply to permission
struct SessionAPI: Sendable {
    let client: APIClient

    // MARK: - Request Bodies

    private struct CreateBody: Encodable {
        let parentID: String?
        let title: String?
    }

    private struct SummarizeBody: Encodable {
        let providerID: String
        let modelID: String
        let auto: Bool?
    }

    private struct ForkBody: Encodable {
        let messageID: String?
    }

    private struct InitBody: Encodable {
        let agent: String?
        let modelID: String?
        let providerID: String?
    }

    private struct RevertBody: Encodable {
        let messageID: String
        let partID: String?
        let snapshot: String?
    }

    private struct PermissionReplyBody: Encodable {
        let response: String
    }

    // MARK: - Endpoints

    /// List all sessions (optionally filtered by directory).
    func list(directory: String? = nil) async throws -> [Session] {
        let queryItems = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/session", queryItems: queryItems))
        return try JSONDecoder().decode([Session].self, from: data)
    }

    /// Create a new session for a specific directory.
    func create(directory: String, title: String? = nil, parentID: String? = nil) async throws -> Session {
        let body = CreateBody(parentID: parentID, title: title)
        let endpoint = APIEndpoint(
            path: "/session",
            method: .POST,
            body: try? JSONEncoder().encode(body),
            queryItems: [URLQueryItem(name: "directory", value: directory)]
        )
        let data = try await client.requestData(endpoint)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Get a single session by ID.
    func get(id: String) async throws -> Session {
        let data = try await client.requestData(.get("/session/\(id)"))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Delete a session.
    func delete(id: String) async throws {
        try await client.requestVoid(.delete("/session/\(id)"))
    }

    /// Abort a running session.
    func abort(id: String) async throws {
        try await client.requestVoid(APIEndpoint(path: "/session/\(id)/abort", method: .POST))
    }

    /// Summarize a session starting from a message.
    /// Trigger context compaction for a session.
    func summarize(id: String, providerID: String, modelID: String, auto: Bool? = nil) async throws -> Bool {
        let data = try await client.requestData(.post("/session/\(id)/summarize", body: SummarizeBody(providerID: providerID, modelID: modelID, auto: auto)))
        return try JSONDecoder().decode(Bool.self, from: data)
    }

    /// Share a session (creates a public share link).
    func share(id: String) async throws -> Session {
        let data = try await client.requestData(APIEndpoint(path: "/session/\(id)/share", method: .POST))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Unshare a session (removes the share link).
    func unshare(id: String) async throws -> Session {
        let data = try await client.requestData(.delete("/session/\(id)/share"))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Fork a session, optionally at a specific message.
    func fork(id: String, messageID: String? = nil) async throws -> Session {
        let data = try await client.requestData(.post("/session/\(id)/fork", body: ForkBody(messageID: messageID)))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Initialize a session with agent/model settings.
    func initialize(
        id: String,
        agent: String? = nil,
        modelID: String? = nil,
        providerID: String? = nil
    ) async throws -> Session {
        let data = try await client.requestData(
            .post(
                "/session/\(id)/init",
                body: InitBody(agent: agent, modelID: modelID, providerID: providerID)
            )
        )
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Revert a session to a specific message/part/snapshot.
    func revert(id: String, messageID: String, partID: String? = nil, snapshot: String? = nil) async throws -> Session {
        let data = try await client.requestData(
            .post(
                "/session/\(id)/revert",
                body: RevertBody(messageID: messageID, partID: partID, snapshot: snapshot)
            )
        )
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Undo a revert on a session.
    func unrevert(id: String) async throws -> Session {
        let data = try await client.requestData(APIEndpoint(path: "/session/\(id)/unrevert", method: .POST))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Get diffs for a session (returns all stored diffs for the session).
    func diff(id: String) async throws -> [FileDiff] {
        let data = try await client.requestData(.get("/session/\(id)/diff"))
        return try JSONDecoder().decode([FileDiff].self, from: data)
    }

    /// Get the status of all sessions (keyed by session ID).
    func status() async throws -> [String: SessionStatus] {
        let data = try await client.requestData(.get("/session/status"))
        return try JSONDecoder().decode([String: SessionStatus].self, from: data)
    }

    /// Reply to a permission request in a session.
    func replyToPermission(sessionID: String, permissionID: String, response: String) async throws {
        try await client.requestVoid(
            .post(
                "/session/\(sessionID)/permissions/\(permissionID)",
                body: PermissionReplyBody(response: response)
            )
        )
    }

    /// Get todos for a session.
    func todos(id: String) async throws -> [TodoItem] {
        let data = try await client.requestData(.get("/session/\(id)/todo"))
        return try JSONDecoder().decode([TodoItem].self, from: data)
    }
}
