import Foundation

// MARK: - PermissionAPI (OpenCode 2.x)

extension PermissionAPI {
    /// Pending requests from a 2.x server — the only permission surface it has.
    func v2List(directory: String?) async throws -> [Permission] {
        let data = try await client.v2Data(.get("/api/permission/request", queryItems: APIEndpoint.v2Location(directory)))
        let list = (data as? [V2Adapter.JSON] ?? []).map(V2Adapter.permission)
        return try V2Adapter.decode([Permission].self, from: list)
    }

    /// 2.x names the reply field `decision` (1.x's experimental route used `reply`).
    func v2Reply(to permission: Permission, decision: PermissionReplyDecision, message: String?) async throws {
        var body: V2Adapter.JSON = ["decision": decision.rawValue]
        if let message { body["message"] = message }
        try await client.requestVoid(
            .v2(
                "/api/session/\(permission.sessionID)/permission/\(permission.id)/reply",
                method: .POST,
                json: body
            )
        )
    }
}

// MARK: - QuestionAPI (OpenCode 2.x)

/// 2.x asks questions through session forms; see `V2Adapter.question(fromForm:)`.
extension QuestionAPI {
    func v2List(directory: String?) async throws -> [QuestionRequest] {
        let data = try await client.v2Data(.get("/api/form", queryItems: APIEndpoint.v2Location(directory)))
        let questions = (data as? [V2Adapter.JSON] ?? []).compactMap(V2Adapter.question(fromForm:))
        return try V2Adapter.decode([QuestionRequest].self, from: questions)
    }

    func v2Reply(requestID: String, sessionID: String, answers: [QuestionAnswer]) async throws {
        // The answer is keyed by field and typed per field, so read the form first.
        let form = try await client.v2Data(.get("/api/session/\(sessionID)/form/\(requestID)")) as? V2Adapter.JSON
        let fields = form?["fields"] as? [V2Adapter.JSON] ?? []
        let answer = V2Adapter.formAnswer(answers, fields: fields)
        try await client.requestVoid(
            .v2("/api/session/\(sessionID)/form/\(requestID)/reply", method: .POST, json: ["answer": answer])
        )
    }

    func v2Reject(requestID: String, sessionID: String) async throws {
        try await client.requestVoid(.delete("/api/session/\(sessionID)/form/\(requestID)"))
    }
}
