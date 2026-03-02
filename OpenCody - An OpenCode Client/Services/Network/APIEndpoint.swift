import Foundation

// MARK: - APIEndpoint

/// Describes an API endpoint with all request parameters.
struct APIEndpoint: Sendable {
    let path: String
    let method: HTTPMethod
    let body: Data?
    let queryItems: [URLQueryItem]?
    let timeoutOverride: TimeInterval?
    let contentType: ContentType

    enum HTTPMethod: String, Sendable {
        case GET, POST, PUT, PATCH, DELETE
    }

    enum ContentType: Sendable {
        case json
        case multipart(boundary: String)
        case none
    }

    init(
        path: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil,
        timeoutOverride: TimeInterval? = nil,
        contentType: ContentType = .json
    ) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
        self.timeoutOverride = timeoutOverride
        self.contentType = contentType
    }
}

// MARK: - Convenience Builders

extension APIEndpoint {
    static func get(_ path: String, queryItems: [URLQueryItem]? = nil) -> APIEndpoint {
        APIEndpoint(path: path, method: .GET, queryItems: queryItems, contentType: .none)
    }

    static func post(_ path: String, body: some Encodable) -> APIEndpoint {
        let data = try? JSONEncoder().encode(body)
        return APIEndpoint(path: path, method: .POST, body: data)
    }

    static func put(_ path: String, body: some Encodable) -> APIEndpoint {
        let data = try? JSONEncoder().encode(body)
        return APIEndpoint(path: path, method: .PUT, body: data)
    }

    static func patch(_ path: String, body: some Encodable) -> APIEndpoint {
        let data = try? JSONEncoder().encode(body)
        return APIEndpoint(path: path, method: .PATCH, body: data)
    }

    static func delete(_ path: String) -> APIEndpoint {
        APIEndpoint(path: path, method: .DELETE, contentType: .none)
    }
}
