import Foundation

// MARK: - QuestionAPI

/// Typed wrapper for question-related endpoints.
///
/// Endpoints:
/// - `GET  /question`                     → list pending questions
/// - `POST /question/{requestID}/reply`   → reply to question
/// - `POST /question/{requestID}/reject`  → reject question
struct QuestionAPI: Sendable {
    let client: APIClient

    private struct ReplyBody: Encodable {
        let answers: [QuestionAnswer]
    }

    /// List all pending questions (optionally filtered by directory).
    func list(directory: String? = nil) async throws -> [QuestionRequest] {
        if client.apiVersion == .v2 { return try await v2List(directory: directory) }
        let queryItems = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/question", queryItems: queryItems))
        return try JSONDecoder().decode([QuestionRequest].self, from: data)
    }

    /// Reply to a question request with answers.
    ///
    /// `directory` must be the session's project directory: pending questions live in
    /// per-directory server instances, and the server routes the request via the
    /// `directory` query param (falling back to its own cwd when absent). Omitting it
    /// sends the reply to the wrong instance, which logs "reply for unknown request".
    /// The reference SDK scopes every call the same way via `x-opencode-directory`.
    ///
    /// `sessionID` is required by OpenCode 2.x, whose questions are session forms.
    func reply(
        requestID: String,
        answers: [QuestionAnswer],
        directory: String? = nil,
        sessionID: String? = nil
    ) async throws {
        if client.apiVersion == .v2 {
            guard let sessionID else { throw OpenCodeError.validation(statusCode: 0, message: "Missing session") }
            return try await v2Reply(requestID: requestID, sessionID: sessionID, answers: answers)
        }
        let body = ReplyBody(answers: answers)
        let encoded = try JSONEncoder().encode(body)
        let endpoint = APIEndpoint(
            path: "/question/\(requestID)/reply",
            method: .POST,
            body: encoded,
            queryItems: directory.map { [URLQueryItem(name: "directory", value: $0)] }
        )
        do {
            try await client.requestVoid(endpoint)
        } catch OpenCodeError.notFound where directory != nil {
            // The question may live in the server's default (cwd) instance —
            // retry unscoped before giving up.
            try await reply(requestID: requestID, answers: answers, directory: nil)
        }
    }

    /// Reject a question request.
    ///
    /// See `reply(requestID:answers:directory:)` for why `directory` is required
    /// to reach the instance holding the pending question.
    func reject(requestID: String, directory: String? = nil, sessionID: String? = nil) async throws {
        if client.apiVersion == .v2 {
            guard let sessionID else { throw OpenCodeError.validation(statusCode: 0, message: "Missing session") }
            return try await v2Reject(requestID: requestID, sessionID: sessionID)
        }
        let endpoint = APIEndpoint(
            path: "/question/\(requestID)/reject",
            method: .POST,
            body: nil,
            queryItems: directory.map { [URLQueryItem(name: "directory", value: $0)] }
        )
        do {
            try await client.requestVoid(endpoint)
        } catch OpenCodeError.notFound where directory != nil {
            try await reject(requestID: requestID, directory: nil)
        }
    }
}
