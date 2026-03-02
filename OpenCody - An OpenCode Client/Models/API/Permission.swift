import Foundation

// MARK: - Permission

/// Maps to `Permission` in types.gen.ts
struct Permission: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let pattern: PermissionPattern?
    let sessionID: String
    let messageID: String
    let callID: String?
    let title: String
    let metadata: [String: AnyCodable]
    let time: PermissionTime
}

// MARK: - PermissionPattern

/// Can be a single string or an array of strings
enum PermissionPattern: Codable, Sendable {
    case single(String)
    case multiple([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            self = .single(single)
        } else if let multiple = try? container.decode([String].self) {
            self = .multiple(multiple)
        } else {
            throw DecodingError.typeMismatch(
                PermissionPattern.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or [String]"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let s):
            try container.encode(s)
        case .multiple(let arr):
            try container.encode(arr)
        }
    }
}

struct PermissionTime: Codable, Sendable {
    let created: Double
}

// MARK: - PermissionReply

/// Used to respond to a permission request
struct PermissionReply: Codable, Sendable {
    let sessionID: String
    let permissionID: String
    let response: String
}
