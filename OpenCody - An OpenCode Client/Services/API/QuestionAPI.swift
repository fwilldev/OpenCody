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
    func reply(requestID: String, answers: [QuestionAnswer], directory: String? = nil) async throws {
        var queryItems: [URLQueryItem]?
        if let directory {
            queryItems = [URLQueryItem(name: "directory", value: directory)]
        }
        let body = ReplyBody(answers: answers)
        let endpoint = APIEndpoint(
            path: "/question/\(requestID)/reply",
            method: .POST,
            body: try JSONEncoder().encode(body),
            queryItems: queryItems
        )
        try await client.requestVoid(endpoint)
    }

    /// Reject a question request.
    func reject(requestID: String, directory: String? = nil) async throws {
        let queryItems = directory.map { [URLQueryItem(name: "directory", value: $0)] }
        let endpoint = APIEndpoint(
            path: "/question/\(requestID)/reject",
            method: .POST,
            body: nil,
            queryItems: queryItems
        )
        try await client.requestVoid(endpoint)
    }
}
