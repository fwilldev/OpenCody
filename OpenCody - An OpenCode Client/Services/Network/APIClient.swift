import Foundation

// MARK: - APIClient

/// Base API client for OpenCode server communication.
///
/// All methods are `nonisolated` to avoid running network I/O on MainActor.
/// The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without
/// explicit `nonisolated` markers, all declarations would be confined to MainActor.
/// All stored properties are immutable (`let`) to satisfy `Sendable`.
nonisolated final class APIClient: Sendable {
    let baseURL: String
    private let authHeader: String?
    var authorizationHeader: String? { authHeader }
    private let session: URLSession

    init(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL

        // Basic Auth header
        if !username.isEmpty || !password.isEmpty {
            let credentials = "\(username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            self.authHeader = "Basic \(encoded)"
        } else {
            self.authHeader = nil
        }

        // URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Generic Request

    /// Execute a typed API request and decode the JSON response.
    func request<T: Decodable & Sendable>(_ endpoint: APIEndpoint) async throws -> T {
        let urlRequest = try buildRequest(endpoint)
        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OpenCodeError.decoding(error)
        }
    }

    /// Execute a request that returns no meaningful body (e.g., DELETE).
    func requestVoid(_ endpoint: APIEndpoint) async throws {
        let urlRequest = try buildRequest(endpoint)
        let (data, response) = try await session.data(for: urlRequest)
        #if DEBUG
        if let httpResp = response as? HTTPURLResponse {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? "<nil>"
            print("[APIClient] requestVoid \(endpoint.method.rawValue) \(endpoint.path) -> \(httpResp.statusCode) body=\(bodyPreview)")
        }
        #endif
        try validateResponse(response, data: data)
    }

    /// Execute a request and return raw `Data` (for non-JSON responses like diffs).
    func requestData(_ endpoint: APIEndpoint) async throws -> Data {
        let urlRequest = try buildRequest(endpoint)
        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)
        return data
    }

    /// Execute a request and return raw `String`.
    func requestString(_ endpoint: APIEndpoint) async throws -> String {
        let data = try await requestData(endpoint)
        guard let string = String(data: data, encoding: .utf8) else {
            throw OpenCodeError.validation(statusCode: 0, message: "Response is not valid UTF-8")
        }
        return string
    }

    // MARK: - SSE Stream Access

    /// Returns URLSession bytes stream for SSE connections.
    /// The caller is responsible for parsing SSE format.
    func streamBytes(_ endpoint: APIEndpoint) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var urlRequest = try buildRequest(endpoint)
        urlRequest.timeoutInterval = 0 // Unlimited for SSE
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return try await session.bytes(for: urlRequest)
    }

    // MARK: - Health Check

    /// Quick health check — returns `true` if server responds 200.
    func healthCheck() async throws -> Bool {
        let endpoint = APIEndpoint.get("/global/health")
        let urlRequest = try buildRequest(endpoint)
        let (_, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    // MARK: - Private Helpers

    private func buildRequest(_ endpoint: APIEndpoint) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + endpoint.path) else {
            throw OpenCodeError.validation(statusCode: 0, message: "Invalid URL: \(baseURL + endpoint.path)")
        }
        components.queryItems = endpoint.queryItems

        guard let url = components.url else {
            throw OpenCodeError.validation(statusCode: 0, message: "Cannot construct URL from components")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body

        if let timeout = endpoint.timeoutOverride {
            request.timeoutInterval = timeout
        }

        // Auth header
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }


        // Content-Type
        switch endpoint.contentType {
        case .json:
            if endpoint.body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        case .multipart(let boundary):
            request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
        case .none:
            break
        }

        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.network(URLError(.badServerResponse))
        }

        let statusCode = httpResponse.statusCode
        let bodyMessage = String(data: data, encoding: .utf8) ?? "Unknown error"

        switch statusCode {
        case 200...299:
            return // Success
        case 401, 403:
            throw OpenCodeError.auth(statusCode: statusCode, message: bodyMessage)
        case 404:
            throw OpenCodeError.notFound(message: bodyMessage)
        case 400:
            // Attempt structured bad-request parsing; fall back to validation
            if let decoded = try? JSONDecoder().decode(BadRequestErrorResponse.self, from: data) {
                throw OpenCodeError.badRequest(errors: decoded.errors)
            }
            throw OpenCodeError.validation(statusCode: statusCode, message: bodyMessage)
        case 409, 422:
            throw OpenCodeError.validation(statusCode: statusCode, message: bodyMessage)
        case 500...599:
            throw OpenCodeError.server(statusCode: statusCode, message: bodyMessage)
        default:
            throw OpenCodeError.server(statusCode: statusCode, message: bodyMessage)
        }
    }
}
