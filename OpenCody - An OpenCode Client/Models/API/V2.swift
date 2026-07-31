import Foundation

// MARK: - V2Envelope

/// Response wrapper used by the `/api/*` (v2) surface: `{ location?, data }`.
///
/// Endpoints under `/api` return their payload nested in `data`, with location
/// metadata attached when the route is location-scoped.
///
/// Deliberately not `Sendable`: the project compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so model conformances are
/// MainActor-isolated and cannot satisfy a `Sendable` generic constraint. This is
/// only ever a transient decode target — the unwrapped `data` is what escapes.
struct V2Envelope<T: Decodable>: Decodable {
    let data: T
    let location: LocationInfo?
    /// Opaque pagination cursors, when the endpoint is paginated.
    let cursor: V2Cursor?
}

/// Opaque pagination cursors returned by paginated v2 endpoints.
struct V2Cursor: Decodable, Sendable {
    let previous: String?
    let next: String?
}

// MARK: - LocationInfo

/// Resolved location for a v2 request. Maps to `LocationInfo`.
struct LocationInfo: Decodable, Sendable {
    let directory: String
    let workspaceID: String?
    let project: LocationProject

    struct LocationProject: Decodable, Sendable {
        let id: String
        let directory: String
    }
}

// MARK: - LocationRef

/// A directory + optional workspace pair. Maps to `LocationRef`.
struct LocationRef: Codable, Sendable {
    let directory: String
    let workspaceID: String?
}

// MARK: - HealthInfo

/// Response of `GET /global/health`.
struct HealthInfo: Decodable, Sendable {
    let healthy: Bool
    let version: String
}

// MARK: - UpgradeResult

/// Response of `POST /global/upgrade` — a success/failure union.
enum UpgradeResult: Decodable, Sendable {
    case success(version: String)
    case failure(error: String)

    private enum CodingKeys: String, CodingKey {
        case success, version, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ok = (try? c.decodeIfPresent(Bool.self, forKey: .success)) ?? false
        if ok {
            self = .success(version: (try? c.decodeIfPresent(String.self, forKey: .version)) ?? "")
        } else {
            self = .failure(error: (try? c.decodeIfPresent(String.self, forKey: .error)) ?? "Upgrade failed")
        }
    }
}

// MARK: - Skill

/// An agent skill exposed by the server. Maps to the `/skill` list item and `SkillV2Info`.
struct Skill: Decodable, Identifiable, Sendable {
    let name: String
    let description: String?
    let location: String
    let content: String
    /// Whether the skill is invocable as a slash command (v2 only).
    let slash: Bool?

    var id: String { name }
}

// MARK: - TextSearchMatch

/// One ripgrep hit from `GET /find`.
struct TextSearchMatch: Decodable, Sendable {
    let path: String
    let line: String
    let lineNumber: Int
    let absoluteOffset: Int
    let submatches: [Submatch]

    struct Submatch: Decodable, Sendable {
        let match: String
        let start: Int
        let end: Int

        private enum CodingKeys: String, CodingKey { case match, start, end }
        private struct TextWrapper: Decodable { let text: String }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            match = (try? c.decode(TextWrapper.self, forKey: .match))?.text ?? ""
            start = (try? c.decode(Int.self, forKey: .start)) ?? 0
            end = (try? c.decode(Int.self, forKey: .end)) ?? 0
        }
    }

    // The server nests `path` and `lines` as `{ text: String }` objects.
    private struct TextWrapper: Decodable { let text: String }

    private enum CodingKeys: String, CodingKey {
        case path, lines, line_number, absolute_offset, submatches
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? c.decode(TextWrapper.self, forKey: .path))?.text ?? ""
        line = (try? c.decode(TextWrapper.self, forKey: .lines))?.text ?? ""
        lineNumber = (try? c.decode(Int.self, forKey: .line_number)) ?? 0
        absoluteOffset = (try? c.decode(Int.self, forKey: .absolute_offset)) ?? 0
        submatches = (try? c.decode([Submatch].self, forKey: .submatches)) ?? []
    }
}

// MARK: - McpResource

/// A resource advertised by a connected MCP server. Maps to `McpResource`.
struct McpResource: Decodable, Identifiable, Sendable {
    let name: String
    let uri: String
    let description: String?
    let mimeType: String?
    let client: String

    var id: String { uri }
}

// MARK: - ConfigProviders

/// Response of `GET /config/providers`.
struct ConfigProvidersResponse: Decodable, Sendable {
    let providers: [Provider]
    /// Default model ID per provider ID.
    let `default`: [String: String]
}
