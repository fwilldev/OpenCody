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
/// - `POST   /session/{id}/shell`      → execute a shell command
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

    private struct ShellBody: Encodable {
        let command: String
        let agent: String
        let model: ShellModelSelection?

        struct ShellModelSelection: Encodable {
            let providerID: String
            let modelID: String
        }
    }

    // MARK: - Endpoints

    /// List sessions (optionally filtered by directory).
    /// - Parameters:
    ///   - directory: Only return sessions for this project directory.
    ///   - roots: When `true`, return root sessions with aggregated summary data (default `true`).
    ///   - limit: Maximum number of sessions to return (default 100).
    func list(directory: String? = nil, roots: Bool = true, limit: Int = 100) async throws -> [Session] {
        var items: [URLQueryItem] = []
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        if roots { items.append(URLQueryItem(name: "roots", value: "true")) }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        let data = try await client.requestData(.get("/session", queryItems: items.isEmpty ? nil : items))
        #if DEBUG
        let preview = String(data: data, encoding: .utf8)?.prefix(3000) ?? "<nil>"
        print("[SessionAPI.list] responseLength=\(data.count) preview=\(preview)")
        #endif
        do {
            let result = try JSONDecoder().decode([Session].self, from: data)
            #if DEBUG
            for s in result {
                print("[SessionAPI.list] session=\(s.id) title=\(s.title.prefix(40)) summary=\(s.summary.map { "files=\($0.files) +\($0.additions) -\($0.deletions)" } ?? "nil")")
            }
            #endif
            return result
        } catch {
            #if DEBUG
            print("[SessionAPI.list] DECODE ERROR: \(error)")
            #endif
            throw error
        }
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
    /// - Parameters:
    ///   - id: The session ID.
    ///   - messageID: Optional message ID to scope the diffs to a specific message.
    func diff(id: String, messageID: String? = nil) async throws -> [FileDiff] {
        var queryItems: [URLQueryItem] = []
        if let messageID { queryItems.append(URLQueryItem(name: "messageID", value: messageID)) }
        let data = try await client.requestData(.get("/session/\(id)/diff", queryItems: queryItems.isEmpty ? nil : queryItems))
        #if DEBUG
        let preview = String(data: data, encoding: .utf8)?.prefix(2000) ?? "<nil>"
        print("[SessionAPI.diff] id=\(id) responseLength=\(data.count) preview=\(preview)")
        #endif
        do {
            let result = try JSONDecoder().decode([FileDiff].self, from: data)
            #if DEBUG
            print("[SessionAPI.diff] decoded \(result.count) diffs")
            #endif
            return result
        } catch {
            #if DEBUG
            print("[SessionAPI.diff] DECODE ERROR: \(error)")
            #endif
            throw error
        }
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

    /// Execute a shell command in the session.
    func shell(id: String, command: String, agent: String, providerID: String? = nil, modelID: String? = nil) async throws {
        var model: ShellBody.ShellModelSelection? = nil
        if let providerID, let modelID {
            model = ShellBody.ShellModelSelection(providerID: providerID, modelID: modelID)
        }
        try await client.requestVoid(.post("/session/\(id)/shell", body: ShellBody(command: command, agent: agent, model: model)))
    }
}
