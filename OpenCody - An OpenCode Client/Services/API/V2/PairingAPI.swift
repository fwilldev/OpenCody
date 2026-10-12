import Foundation

// MARK: - PairingAPI (OpenCode 2.x)

/// Pairing links: `POST /api/pair` creates a short-lived, single-use
/// `/auth/connect/{code}` link; redeeming it returns a session token that works as
/// the basic-auth password for the user `opencode` (valid for about 30 days).
nonisolated enum PairingAPI {
    /// The only username a 2.x server accepts.
    static let username = "opencode"

    struct Link: Equatable, Sendable {
        /// Server root, including any reverse-proxy path prefix.
        let server: URL
        let code: String
    }

    /// Parse a pairing link (`https://host:4096/auth/connect/<code>`).
    static func parse(_ text: String) -> Link? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil,
              let range = url.path.range(of: "/auth/connect/") else { return nil }
        let code = String(url.path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !code.isEmpty, !code.contains("/"),
              var root = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        root.path = String(url.path[..<range.lowerBound])
        root.query = nil
        root.fragment = nil
        guard let server = root.url else { return nil }
        return Link(server: server, code: code)
    }

    /// Redeem a link for a session token. Codes are single-use.
    static func redeem(_ link: Link) async throws -> String {
        let client = APIClient(baseURL: link.server.absoluteString, username: "", password: "", apiVersion: .v2)
        let data = try await client.requestData(.get("/auth/connect/\(link.code)"))
        guard let token = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String,
              !token.isEmpty else {
            throw OpenCodeError.connectionFailed("The server didn't return a token for this pairing link.")
        }
        return token
    }

    /// Create a pairing link for another device. Needs an authenticated client.
    static func createLink(client: APIClient) async throws -> (url: URL, expiresIn: Int) {
        let body = try await client.v2JSON(.v2("/api/pair", method: .POST)) as? [String: Any] ?? [:]
        guard let code = body["code"] as? String,
              let url = URL(string: client.baseURL + "/auth/connect/" + code) else {
            throw OpenCodeError.connectionFailed("The server didn't return a pairing code.")
        }
        return (url, body["expires_in"] as? Int ?? 300)
    }
}
