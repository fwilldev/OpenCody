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
        let queryItems = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let data = try await client.requestData(.get("/question", queryItems: queryItems))
        return try JSONDecoder().decode([QuestionRequest].self, from: data)
    }

    /// Reply to a question request with answers.
    ///
    /// The reference web UI does **not** pass `directory` for reply/reject calls,
    /// so we omit it to match the canonical client behaviour.
    func reply(requestID: String, answers: [QuestionAnswer]) async throws {
        let body = ReplyBody(answers: answers)
        let encoded = try JSONEncoder().encode(body)
        #if DEBUG
        let bodyPreview = String(data: encoded, encoding: .utf8) ?? "<nil>"
        print("[QuestionAPI] reply requestID=\(requestID) body=\(bodyPreview)")
        #endif
        let endpoint = APIEndpoint(
            path: "/question/\(requestID)/reply",
            method: .POST,
            body: encoded
        )
        try await client.requestVoid(endpoint)
    }

    /// Reject a question request.
    ///
    /// The reference web UI does **not** pass `directory` for reply/reject calls,
    /// so we omit it to match the canonical client behaviour.
    func reject(requestID: String) async throws {
        #if DEBUG
        print("[QuestionAPI] reject requestID=\(requestID)")
        #endif
        let endpoint = APIEndpoint(
            path: "/question/\(requestID)/reject",
            method: .POST,
            body: nil
        )
        try await client.requestVoid(endpoint)
    }
}
