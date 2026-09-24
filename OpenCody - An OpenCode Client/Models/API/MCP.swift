import Foundation

// MARK: - McpStatus

/// MCP server status, discriminated union.
/// McpStatusConnected | McpStatusDisabled | McpStatusFailed | McpStatusNeedsAuth | McpStatusNeedsClientRegistration
enum McpStatus: Codable, Sendable, Equatable {
    case connected
    case disabled
    case failed(error: String)
    case needsAuth
    case needsClientRegistration(error: String)
    /// A status this build does not know. The `/mcp` response is a map, so one
    /// unrecognised entry must not take the whole list down.
    case unknown(status: String)

    var statusString: String {
        switch self {
        case .connected: return "connected"
        case .disabled: return "disabled"
        case .failed: return "failed"
        case .needsAuth: return "needs_auth"
        case .needsClientRegistration: return "needs_client_registration"
        case .unknown(let status): return status
        }
    }

    /// The server-supplied failure detail, when there is one.
    var errorDetail: String? {
        switch self {
        case .failed(let error), .needsClientRegistration(let error): return error
        default: return nil
        }
    }

    var isConnected: Bool { self == .connected }

    /// Whether tapping "Connect" can plausibly change this status.
    ///
    /// `needsAuth` and `needsClientRegistration` cannot be resolved by reconnecting —
    /// they need credentials the client has to supply first — so the UI must not
    /// offer a retry that is guaranteed to land on the same status again.
    var isConnectActionable: Bool {
        switch self {
        case .disabled, .failed, .unknown: return true
        case .connected, .needsAuth, .needsClientRegistration: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "connected":
            self = .connected
        case "disabled":
            self = .disabled
        case "failed":
            // Be tolerant: the detail is documented as required, but a missing one
            // is no reason to fail the whole map.
            self = .failed(error: try container.decodeIfPresent(String.self, forKey: .error) ?? "Unknown error")
        case "needs_auth":
            self = .needsAuth
        case "needs_client_registration":
            self = .needsClientRegistration(
                error: try container.decodeIfPresent(String.self, forKey: .error) ?? "Client registration failed"
            )
        default:
            self = .unknown(status: status)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .connected:
            try container.encode("connected", forKey: .status)
        case .disabled:
            try container.encode("disabled", forKey: .status)
        case .failed(let error):
            try container.encode("failed", forKey: .status)
            try container.encode(error, forKey: .error)
        case .needsAuth:
            try container.encode("needs_auth", forKey: .status)
        case .needsClientRegistration(let error):
            try container.encode("needs_client_registration", forKey: .status)
            try container.encode(error, forKey: .error)
        case .unknown(let status):
            try container.encode(status, forKey: .status)
        }
    }
}

// MARK: - LspStatus

struct LspStatus: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let root: String
    let status: LspConnectionStatus
}

enum LspConnectionStatus: String, Codable, Sendable {
    case connected
    case error
}

// MARK: - FormatterStatus

struct FormatterStatus: Codable, Sendable {
    let name: String
    let extensions: [String]
    let enabled: Bool
}
