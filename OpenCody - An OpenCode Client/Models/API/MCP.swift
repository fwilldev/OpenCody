import Foundation

// MARK: - McpStatus

/// MCP server status, discriminated union.
/// McpStatusConnected | McpStatusDisabled | McpStatusFailed | McpStatusNeedsAuth | McpStatusNeedsClientRegistration
enum McpStatus: Codable, Sendable {
    case connected
    case disabled
    case failed(error: String)
    case needsAuth
    case needsClientRegistration(error: String)

    var statusString: String {
        switch self {
        case .connected: return "connected"
        case .disabled: return "disabled"
        case .failed: return "failed"
        case .needsAuth: return "needs_auth"
        case .needsClientRegistration: return "needs_client_registration"
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
            let error = try container.decode(String.self, forKey: .error)
            self = .failed(error: error)
        case "needs_auth":
            self = .needsAuth
        case "needs_client_registration":
            let error = try container.decode(String.self, forKey: .error)
            self = .needsClientRegistration(error: error)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Unknown MCP status: \(status)"
            )
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
