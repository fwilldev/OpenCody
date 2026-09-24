import Foundation

// MARK: - V2 Request Helpers

extension APIClient {
    /// Session sharing — 2.x has no share links.
    var supportsSessionSharing: Bool { apiVersion == .v1 }
    /// Archiving sessions — 2.x records `time.archived` but has no route to set it.
    var supportsSessionArchiving: Bool { apiVersion == .v1 }

    /// Perform a request and return the parsed JSON body.
    func v2JSON(_ endpoint: APIEndpoint) async throws -> Any {
        try V2Adapter.object(from: try await requestData(endpoint))
    }

    /// Perform a request and return the `data` member of its envelope.
    func v2Data(_ endpoint: APIEndpoint) async throws -> Any {
        try V2Adapter.envelope(from: try await requestData(endpoint))
    }
}

extension APIEndpoint {
    /// Build a JSON-body endpoint from an already-assembled JSON value.
    static func v2(
        _ path: String,
        method: HTTPMethod,
        json: Any? = nil,
        queryItems: [URLQueryItem]? = nil,
        timeout: TimeInterval? = nil
    ) -> APIEndpoint {
        let body = json.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
        return APIEndpoint(
            path: path,
            method: method,
            body: body,
            queryItems: queryItems,
            timeoutOverride: timeout,
            contentType: body == nil ? .none : .json
        )
    }

    /// The 2.x location selector, `location[directory]=…`.
    ///
    /// Location-scoped 2.x routes resolve which project answers from this parameter,
    /// falling back to the server's own working directory — the same trap the v1
    /// `directory` parameter has.
    static func v2Location(_ directory: String?, _ extra: [URLQueryItem] = []) -> [URLQueryItem]? {
        var items: [URLQueryItem] = []
        if let directory, !directory.isEmpty {
            items.append(URLQueryItem(name: "location[directory]", value: directory))
        }
        items.append(contentsOf: extra)
        return items.isEmpty ? nil : items
    }
}
