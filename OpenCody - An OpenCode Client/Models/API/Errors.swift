import Foundation

// MARK: - APIError

/// Application-level errors for the OpenCode client.
enum OpenCodeError: Error, LocalizedError, Sendable {
    /// Network-level error (no response received)
    case network(any Error)

    /// Authentication error (401, 403)
    case auth(statusCode: Int, message: String)

    /// Server error (5xx)
    case server(statusCode: Int, message: String)

    /// Validation/client error (4xx other than auth)
    case validation(statusCode: Int, message: String)

    /// SSE stream error
    case sse(String)

    /// Not found (404)
    case notFound(message: String)

    /// Bad request with structured errors
    case badRequest(errors: [[String: AnyCodable]])

    /// Decoding error
    case decoding(any Error)

    /// Connection to OpenCode server failed
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .auth(let code, let message):
            return "Authentication error (\(code)): \(message)"
        case .server(let code, let message):
            return "Server error (\(code)): \(message)"
        case .validation(let code, let message):
            return "Validation error (\(code)): \(message)"
        case .sse(let message):
            return "SSE error: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .badRequest:
            return "Bad request"
        case .decoding(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        }
    }
}

// MARK: - BadRequestError

/// Maps to `BadRequestError` in types.gen.ts
struct BadRequestErrorResponse: Codable, Sendable {
    let data: AnyCodable?
    let errors: [[String: AnyCodable]]
    let success: Bool
}

// MARK: - NotFoundError

/// Maps to `NotFoundError` in types.gen.ts
struct NotFoundErrorResponse: Codable, Sendable {
    let name: String
    let data: NotFoundErrorData
}

struct NotFoundErrorData: Codable, Sendable {
    let message: String
}
