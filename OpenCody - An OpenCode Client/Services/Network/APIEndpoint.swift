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

// MARK: - Path Segments

extension APIEndpoint {
    /// Percent-encode a value for use as a single path segment.
    ///
    /// Server-side identifiers are frequently user-chosen strings — MCP server names
    /// and provider IDs are config-file keys, so they can contain anything. Foundation
    /// tolerates a raw space (it encodes it), but `#` and `?` truncate the path:
    /// `/mcp/a#b/connect` parses with path `/mcp/a` and the rest read as a fragment,
    /// which hits a different route and, for `?`, also discards the `directory` query.
    /// A raw `/` quietly turns into an extra path segment. Route every dynamic segment
    /// through here.
    static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathSegmentAllowed) ?? value
    }
}

extension CharacterSet {
    /// Unreserved characters plus the sub-delims that are safe inside one path segment.
    /// Deliberately excludes `/`, `?`, `#`, `%` and `;`.
    fileprivate static let urlPathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~!$&'()*+,=@")
        return set
    }()
}

// MARK: - Convenience Builders

extension APIEndpoint {
    static func get(_ path: String, queryItems: [URLQueryItem]? = nil) -> APIEndpoint {
        APIEndpoint(path: path, method: .GET, queryItems: queryItems, contentType: .none)
    }

    static func post(_ path: String, body: some Encodable, queryItems: [URLQueryItem]? = nil) -> APIEndpoint {
        let data = try? JSONEncoder().encode(body)
        return APIEndpoint(path: path, method: .POST, body: data, queryItems: queryItems)
    }

    /// A bodyless POST — used by the many action endpoints that take only path and query.
    static func post(_ path: String, queryItems: [URLQueryItem]? = nil) -> APIEndpoint {
        APIEndpoint(path: path, method: .POST, queryItems: queryItems, contentType: .none)
    }

    static func put(_ path: String, body: some Encodable, queryItems: [URLQueryItem]? = nil) -> APIEndpoint {
        let data = try? JSONEncoder().encode(body)
        return APIEndpoint(path: path, method: .PUT, body: data, queryItems: queryItems)
    }

    static func patch(_ path: String, body: some Encodable, queryItems: [URLQueryItem]? = nil) -> APIEndpoint {
        let data = try? JSONEncoder().encode(body)
        return APIEndpoint(path: path, method: .PATCH, body: data, queryItems: queryItems)
    }

    static func delete(_ path: String, queryItems: [URLQueryItem]? = nil) -> APIEndpoint {
        APIEndpoint(path: path, method: .DELETE, queryItems: queryItems, contentType: .none)
    }
}
