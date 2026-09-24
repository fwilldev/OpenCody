import Foundation

// MARK: - SessionAPI

/// Typed wrapper for all session-related REST endpoints.
///
/// Endpoints:
/// - `GET    /session`                  → list sessions
/// - `POST   /session`                  → create a session
/// - `GET    /session/status`            → status of all sessions
/// - `GET    /session/{id}`              → get one session
/// - `PATCH  /session/{id}`              → update title / metadata / archived
/// - `DELETE /session/{id}`              → delete a session
/// - `GET    /session/{id}/children`     → child (subagent) sessions
/// - `GET    /session/{id}/todo`         → todo list
/// - `GET    /session/{id}/diff`         → file diffs
/// - `POST   /session/{id}/abort`        → abort a running session
/// - `POST   /session/{id}/init`         → write AGENTS.md for the project
/// - `POST   /session/{id}/fork`         → fork at a message
/// - `POST   /session/{id}/share`        → create a share link
/// - `DELETE /session/{id}/share`        → remove the share link
/// - `POST   /session/{id}/summarize`    → compact the conversation
/// - `POST   /session/{id}/revert`       → revert to a message
/// - `POST   /session/{id}/unrevert`     → restore reverted messages
/// - `POST   /session/{id}/shell`        → run a shell command in session context
/// - `GET    /experimental/session`      → sessions across all projects
/// - `POST   /experimental/session/{id}/background` → detach blocking subagents
struct SessionAPI: Sendable {
    let client: APIClient

    /// Project directory that scopes every request made through this instance.
    ///
    /// The server resolves *which project instance* answers a request from the
    /// `directory` query parameter. Omitting it makes the server fall back to its
    /// own working directory, so a server started outside the project — or serving
    /// several projects — silently answers for the wrong one: `/diff` and `/todo`
    /// come back empty even though the session has changes.
    ///
    /// It is a stored property rather than a per-method argument so a new endpoint
    /// cannot forget to send it. Always pass `session.directory` (or the project
    /// worktree) when one is in scope.
    let directory: String?

    init(client: APIClient, directory: String? = nil) {
        self.client = client
        self.directory = directory
    }

    /// Query items for a request, always carrying `directory` when known.
    private func query(_ extra: [URLQueryItem] = []) -> [URLQueryItem]? {
        var items: [URLQueryItem] = []
        if let directory { items.append(URLQueryItem(name: "directory", value: directory)) }
        items.append(contentsOf: extra)
        return items.isEmpty ? nil : items
    }

    /// A JSON-body endpoint scoped to `directory`.
    ///
    /// The `.post`/`.patch` convenience builders on `APIEndpoint` take no query
    /// items, so body-carrying session routes are built here to keep `directory`
    /// attached.
    private func scoped(
        _ path: String,
        method: APIEndpoint.HTTPMethod,
        body: some Encodable,
        timeout: TimeInterval? = nil
    ) throws -> APIEndpoint {
        APIEndpoint(
            path: path,
            method: method,
            body: try JSONEncoder().encode(body),
            queryItems: query(),
            timeoutOverride: timeout
        )
    }

    // MARK: - Request Bodies

    /// Model reference used by session create / prompt bodies.
    struct ModelRef: Encodable, Sendable {
        let providerID: String
        /// The model identifier. `POST /session` names this key `id`.
        let id: String
        let variant: String?

        init(providerID: String, id: String, variant: String? = nil) {
            self.providerID = providerID
            self.id = id
            self.variant = variant
        }
    }

    private struct CreateBody: Encodable {
        let parentID: String?
        let title: String?
        let agent: String?
        let model: ModelRef?
        let workspaceID: String?
    }

    private struct SummarizeBody: Encodable {
        let providerID: String
        let modelID: String
        let auto: Bool?
    }

    private struct ForkBody: Encodable {
        let messageID: String?
    }

    /// `POST /session/{id}/init` — all three fields are required by the server.
    private struct InitBody: Encodable {
        let modelID: String
        let providerID: String
        let messageID: String
    }

    /// `POST /session/{id}/revert` — `snapshot` is no longer part of the schema.
    private struct RevertBody: Encodable {
        let messageID: String
        let partID: String?
    }

    private struct UpdateBody: Encodable {
        let title: String?
        let time: UpdateTimeBody?

        struct UpdateTimeBody: Encodable {
            /// Wrap in `ExplicitNull` to encode `nil` as JSON `null` (for unarchiving)
            /// rather than omitting the key.
            let archived: ExplicitNull<Double>?

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let archived {
                    try container.encode(archived, forKey: .archived)
                }
            }

            enum CodingKeys: String, CodingKey {
                case archived
            }
        }
    }

    /// Wrapper that encodes `nil` as JSON `null` instead of omitting the key.
    private enum ExplicitNull<T: Encodable>: Encodable {
        case value(T)
        case null

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .value(let val):
                try container.encode(val)
            case .null:
                try container.encodeNil()
            }
        }
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

    // MARK: - Listing

    /// List sessions (optionally filtered by directory).
    /// - Parameters:
    ///   - directory: Only return sessions for this project directory.
    ///   - roots: When `true`, return root sessions with aggregated summary data.
    ///   - limit: Maximum number of sessions to return.
    ///   - start: Pagination offset — skip this many sessions before returning results.
    ///   - search: Free-text filter applied server-side.
    func list(
        roots: Bool = true,
        limit: Int = 100,
        start: Int? = nil,
        search: String? = nil
    ) async throws -> [Session] {
        if client.apiVersion == .v2 { return try await v2List(roots: roots, limit: limit, start: start, search: search) }
        var extra: [URLQueryItem] = []
        if roots { extra.append(URLQueryItem(name: "roots", value: "true")) }
        extra.append(URLQueryItem(name: "limit", value: String(limit)))
        if let start { extra.append(URLQueryItem(name: "start", value: String(start))) }
        if let search, !search.isEmpty { extra.append(URLQueryItem(name: "search", value: search)) }
        let data = try await client.requestData(.get("/session", queryItems: query(extra)))
        return try JSONDecoder().decode([Session].self, from: data)
    }

    /// List sessions across every known project.
    ///
    /// `GET /experimental/session` returns `GlobalSession`, which is a `Session`
    /// plus a `project` summary. Archived sessions are excluded unless requested.
    func listGlobal(
        roots: Bool = true,
        limit: Int = 100,
        cursor: Int? = nil,
        search: String? = nil,
        archived: Bool = false
    ) async throws -> [GlobalSession] {
        if client.apiVersion == .v2 { return try await v2ListGlobal(roots: roots, limit: limit, search: search, archived: archived) }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "roots", value: roots ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: String(cursor))) }
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        if archived { items.append(URLQueryItem(name: "archived", value: "true")) }
        let data = try await client.requestData(.get("/experimental/session", queryItems: items))
        return try JSONDecoder().decode([GlobalSession].self, from: data)
    }

    /// Get the status of all sessions (keyed by session ID).
    func status() async throws -> [String: SessionStatus] {
        if client.apiVersion == .v2 { return try await v2Status() }
        let data = try await client.requestData(.get("/session/status", queryItems: query()))
        return try JSONDecoder().decode([String: SessionStatus].self, from: data)
    }

    // MARK: - CRUD

    /// Create a new session for a specific directory.
    /// - Parameters:
    ///   - directory: Project directory the session belongs to.
    ///   - title: Optional initial title.
    ///   - parentID: Parent session when creating a child/subagent session.
    ///   - agent: Agent to bind the session to.
    ///   - model: Model to bind the session to.
    func create(
        title: String? = nil,
        parentID: String? = nil,
        agent: String? = nil,
        model: ModelRef? = nil,
        workspaceID: String? = nil
    ) async throws -> Session {
        if client.apiVersion == .v2 { return try await v2Create(title: title, agent: agent, model: model) }
        let body = CreateBody(
            parentID: parentID,
            title: title,
            agent: agent,
            model: model,
            workspaceID: workspaceID
        )
        let endpoint = APIEndpoint(
            path: "/session",
            method: .POST,
            body: try JSONEncoder().encode(body),
            queryItems: query()
        )
        let data = try await client.requestData(endpoint)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Get a single session by ID.
    func get(id: String) async throws -> Session {
        if client.apiVersion == .v2 { return try await v2Get(id: id) }
        let data = try await client.requestData(.get("/session/\(id)", queryItems: query()))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Delete a session and all of its data.
    func delete(id: String) async throws {
        if client.apiVersion == .v2 { return try await v2Delete(id: id) }
        try await client.requestVoid(APIEndpoint(path: "/session/\(id)", method: .DELETE, queryItems: query(), contentType: .none))
    }

    /// Update a session (title, archived status).
    /// - Parameters:
    ///   - id: The session ID.
    ///   - title: New title, or `nil` to leave unchanged.
    ///   - setArchived: `true` to archive (sets timestamp), `false` to unarchive (sends JSON null).
    ///                  Pass `nil` to leave the archived status unchanged.
    func update(id: String, title: String? = nil, setArchived: Bool? = nil) async throws -> Session {
        if client.apiVersion == .v2 { return try await v2Update(id: id, title: title, setArchived: setArchived) }
        let timeBody: UpdateBody.UpdateTimeBody? = setArchived.map { archive in
            UpdateBody.UpdateTimeBody(
                archived: archive ? .value(Date().timeIntervalSince1970) : .null
            )
        }
        let body = UpdateBody(title: title, time: timeBody)
        let data = try await client.requestData(try scoped("/session/\(id)", method: .PATCH, body: body))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Get the child sessions forked from (or spawned as subagents of) a session.
    func children(id: String) async throws -> [Session] {
        if client.apiVersion == .v2 { return try await v2Children(id: id) }
        let data = try await client.requestData(.get("/session/\(id)/children", queryItems: query()))
        return try JSONDecoder().decode([Session].self, from: data)
    }

    // MARK: - Run Control

    /// Abort a running session.
    func abort(id: String) async throws {
        if client.apiVersion == .v2 { return try await v2Abort(id: id) }
        try await client.requestVoid(APIEndpoint(path: "/session/\(id)/abort", method: .POST, queryItems: query()))
    }

    /// Detach any synchronous subagents currently blocking the session so they
    /// continue in the background.
    func backgroundSubagents(id: String) async throws {
        if client.apiVersion == .v2 { return try await v2BackgroundSubagents(id: id) }
        try await client.requestVoid(
            APIEndpoint(path: "/experimental/session/\(id)/background", method: .POST, queryItems: query())
        )
    }

    /// Compact the session's context via AI summarization.
    /// - Returns: `true` when the server accepted the request.
    func summarize(id: String, providerID: String, modelID: String, auto: Bool? = nil) async throws -> Bool {
        if client.apiVersion == .v2 { return try await v2Summarize(id: id) }
        let data = try await client.requestData(
            try scoped(
                "/session/\(id)/summarize",
                method: .POST,
                body: SummarizeBody(providerID: providerID, modelID: modelID, auto: auto)
            )
        )
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? true
    }

    /// Analyze the project and write an `AGENTS.md` file.
    ///
    /// - Parameter messageID: ID to attach the generated message to. A fresh
    ///   `msg_`-prefixed identifier is generated when omitted.
    /// - Returns: `true` when the server accepted the request.
    @discardableResult
    func initialize(
        id: String,
        providerID: String,
        modelID: String,
        messageID: String? = nil
    ) async throws -> Bool {
        if client.apiVersion == .v2 {
            // 2.x ships AGENTS.md generation as the built-in `init` command.
            try await CommandAPI(client: client).v2Execute(sessionID: id, command: "init", arguments: "")
            return true
        }
        let body = InitBody(
            modelID: modelID,
            providerID: providerID,
            messageID: messageID ?? IDGenerator.message()
        )
        let data = try await client.requestData(try scoped("/session/\(id)/init", method: .POST, body: body))
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? true
    }

    // MARK: - Sharing

    /// Share a session (creates a public share link).
    func share(id: String) async throws -> Session {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Session sharing") }
        let data = try await client.requestData(APIEndpoint(path: "/session/\(id)/share", method: .POST, queryItems: query()))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Unshare a session (removes the share link).
    func unshare(id: String) async throws {
        if client.apiVersion == .v2 { throw OpenCodeError.unsupported("Session sharing") }
        try await client.requestVoid(APIEndpoint(path: "/session/\(id)/share", method: .DELETE, queryItems: query(), contentType: .none))
    }

    // MARK: - History

    /// Fork a session, optionally at a specific message.
    func fork(id: String, messageID: String? = nil) async throws -> Session {
        if client.apiVersion == .v2 { return try await v2Fork(id: id, messageID: messageID) }
        let data = try await client.requestData(try scoped("/session/\(id)/fork", method: .POST, body: ForkBody(messageID: messageID)))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Revert the session to the state before a specific message (or part).
    func revert(id: String, messageID: String, partID: String? = nil) async throws -> Session {
        if client.apiVersion == .v2 { return try await v2Revert(id: id, messageID: messageID) }
        let data = try await client.requestData(
            try scoped("/session/\(id)/revert", method: .POST, body: RevertBody(messageID: messageID, partID: partID))
        )
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Restore all previously reverted messages.
    func unrevert(id: String) async throws -> Session {
        if client.apiVersion == .v2 { return try await v2Unrevert(id: id) }
        let data = try await client.requestData(APIEndpoint(path: "/session/\(id)/unrevert", method: .POST, queryItems: query()))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    /// Get the diffs produced by one user message.
    ///
    /// - Important: `messageID` is **required** despite being optional in the
    ///   OpenAPI document. The server's handler starts with
    ///   `if (!input.messageID) return []`, so omitting it always yields an empty
    ///   array, and there is no whole-session variant of this route. For a
    ///   session-wide view build a `SessionChangeSet` from the session's messages
    ///   instead — the per-turn diffs are already included in
    ///   `GET /session/{id}/message`.
    ///
    /// - Parameters:
    ///   - id: The session ID.
    ///   - messageID: The **user** message whose changes to return. Passing an
    ///     assistant message ID also yields an empty array.
    func diff(id: String, messageID: String) async throws -> [FileDiff] {
        if client.apiVersion == .v2 { return try await v2Diff(id: id, messageID: messageID) }
        let data = try await client.requestData(
            .get(
                "/session/\(id)/diff",
                queryItems: query([URLQueryItem(name: "messageID", value: messageID)])
            )
        )
        return try JSONDecoder().decode([FileDiff].self, from: data)
    }

    /// Get todos for a session.
    func todos(id: String) async throws -> [TodoItem] {
        // 2.x has no todo list.
        if client.apiVersion == .v2 { return [] }
        let data = try await client.requestData(.get("/session/\(id)/todo", queryItems: query()))
        return try JSONDecoder().decode([TodoItem].self, from: data)
    }

    // MARK: - Shell

    /// Execute a shell command within the session context.
    func shell(
        id: String,
        command: String,
        agent: String,
        providerID: String? = nil,
        modelID: String? = nil
    ) async throws {
        if client.apiVersion == .v2 { return try await v2Shell(id: id, command: command) }
        var model: ShellBody.ShellModelSelection? = nil
        if let providerID, let modelID {
            model = ShellBody.ShellModelSelection(providerID: providerID, modelID: modelID)
        }
        try await client.requestVoid(
            try scoped("/session/\(id)/shell", method: .POST, body: ShellBody(command: command, agent: agent, model: model), timeout: 300)
        )
    }
}
