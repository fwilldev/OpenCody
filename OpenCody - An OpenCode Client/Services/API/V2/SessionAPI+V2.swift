import Foundation

// MARK: - SessionAPI (OpenCode 2.x)

/// 2.x implementations of `SessionAPI`, reached through `client.apiVersion == .v2`.
///
/// Session routes in 2.x resolve their location from the session itself, so no
/// directory is sent; only listing filters by it.
extension SessionAPI {
    private typealias JSON = V2Adapter.JSON

    private func v2Sessions(_ items: [URLQueryItem]) async throws -> [Session] {
        let data = try await client.v2Data(.get("/api/session", queryItems: items))
        let list = data as? [JSON] ?? []
        return try V2Adapter.decode([Session].self, from: list.map(V2Adapter.session))
    }

    func v2List(roots: Bool, limit: Int, start: Int?, search: String?) async throws -> [Session] {
        // 2.x pages by cursor, not offset: ask for the whole window and drop the head.
        let offset = max(0, start ?? 0)
        var items = [
            URLQueryItem(name: "limit", value: String(limit + offset)),
            URLQueryItem(name: "order", value: "desc"),
        ]
        if let directory, !directory.isEmpty { items.append(URLQueryItem(name: "directory", value: directory)) }
        if roots { items.append(URLQueryItem(name: "parentID", value: "null")) }
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        return Array(try await v2Sessions(items).dropFirst(offset))
    }

    func v2ListGlobal(roots: Bool, limit: Int, search: String?, archived: Bool) async throws -> [GlobalSession] {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: "desc"),
        ]
        if roots { items.append(URLQueryItem(name: "parentID", value: "null")) }
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }

        let query = items
        async let sessionData = client.v2Data(.get("/api/session", queryItems: query))
        async let projectData = client.v2JSON(.get("/api/project"))
        let sessions = try await sessionData as? [JSON] ?? []
        let projects = (try? await projectData) as? [JSON] ?? []
        let projectsByID = Dictionary(
            projects.compactMap { p in (p["id"] as? String).map { ($0, p) } },
            uniquingKeysWith: { first, _ in first }
        )

        let global: [JSON] = sessions.compactMap { raw in
            let isArchived = (raw["time"] as? JSON)?["archived"] != nil
            if isArchived != archived { return nil }
            var session = V2Adapter.session(raw)
            if let projectID = raw["projectID"] as? String, let project = projectsByID[projectID] {
                var summary: JSON = ["id": projectID, "worktree": project["canonical"] ?? ""]
                if let name = project["name"] { summary["name"] = name }
                session["project"] = summary
            }
            return session
        }
        return try V2Adapter.decode([GlobalSession].self, from: global)
    }

    func v2Status() async throws -> [String: SessionStatus] {
        let data = try await client.v2Data(.get("/api/session/active"))
        let active = data as? JSON ?? [:]
        // Only running sessions are listed; everything else is idle.
        var result: [String: SessionStatus] = [:]
        for (id, _) in active { result[id] = .busy }
        return result
    }

    func v2Create(title: String?, agent: String?, model: ModelRef?) async throws -> Session {
        var body: JSON = [:]
        if let title { body["title"] = title }
        if let agent { body["agent"] = agent }
        if let model {
            var ref: JSON = ["id": model.id, "providerID": model.providerID]
            if let variant = model.variant { ref["variant"] = variant }
            body["model"] = ref
        }
        if let directory, !directory.isEmpty { body["location"] = ["directory": directory] }
        let data = try await client.v2Data(.v2("/api/session", method: .POST, json: body))
        return try V2Adapter.decode(Session.self, from: V2Adapter.session(data as? JSON ?? [:]))
    }

    func v2Get(id: String) async throws -> Session {
        let data = try await client.v2Data(.get("/api/session/\(id)"))
        return try V2Adapter.decode(Session.self, from: V2Adapter.session(data as? JSON ?? [:]))
    }

    func v2Delete(id: String) async throws {
        try await client.requestVoid(.delete("/api/session/\(id)"))
    }

    func v2Update(id: String, title: String?, setArchived: Bool?) async throws -> Session {
        if setArchived != nil {
            // 2.x records `time.archived` but exposes no route to change it.
            throw OpenCodeError.unsupported("Archiving sessions")
        }
        if let title {
            try await client.requestVoid(.v2("/api/session/\(id)", method: .PATCH, json: ["title": title]))
        }
        return try await v2Get(id: id)
    }

    func v2Children(id: String) async throws -> [Session] {
        try await v2Sessions([URLQueryItem(name: "parentID", value: id)])
    }

    func v2Abort(id: String) async throws {
        try await client.requestVoid(.post("/api/session/\(id)/interrupt"))
    }

    func v2BackgroundSubagents(id: String) async throws {
        try await client.requestVoid(.post("/api/session/\(id)/background"))
    }

    /// 2.x compacts with the session's own model; the model arguments do not apply.
    func v2Summarize(id: String) async throws -> Bool {
        try await client.requestVoid(.v2("/api/session/\(id)/compact", method: .POST, json: JSON()))
        return true
    }

    func v2Fork(id: String, messageID: String?) async throws -> Session {
        var body: JSON = [:]
        if let messageID { body["before"] = messageID }
        let data = try await client.v2Data(.v2("/api/session/\(id)/fork", method: .POST, json: body))
        return try V2Adapter.decode(Session.self, from: V2Adapter.session(data as? JSON ?? [:]))
    }

    /// v1 revert is a staged, undoable state — exactly 2.x's `revert/stage`.
    func v2Revert(id: String, messageID: String) async throws -> Session {
        _ = try await client.requestData(
            .v2("/api/session/\(id)/revert/stage", method: .POST, json: ["messageID": messageID])
        )
        return try await v2Get(id: id)
    }

    /// v1 unrevert drops the staged revert — 2.x's `DELETE …/revert`.
    func v2Unrevert(id: String) async throws -> Session {
        try await client.requestVoid(.delete("/api/session/\(id)/revert"))
        return try await v2Get(id: id)
    }

    func v2Diff(id: String, messageID: String) async throws -> [FileDiff] {
        let data = try await client.v2Data(
            .get("/api/session/\(id)/diff", queryItems: [URLQueryItem(name: "from", value: messageID)])
        )
        // `FileDiff.Info` has the same fields as v1 `FileDiff`.
        return try V2Adapter.decode([FileDiff].self, from: data)
    }

    func v2Shell(id: String, command: String) async throws {
        try await client.requestVoid(
            .v2("/api/session/\(id)/shell", method: .POST, json: ["command": command], timeout: 300)
        )
    }
}
