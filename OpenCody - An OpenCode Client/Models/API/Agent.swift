import Foundation

// MARK: - Agent

/// Maps to `Agent` in types.gen.ts
struct Agent: Codable, Identifiable, Sendable {
    let name: String
    let description: String?
    let mode: AgentMode
    let color: String?
    let permission: [AgentPermissionEntry]
    let model: AgentModel?
    let prompt: String?
    let options: [String: AnyCodable]
    let hidden: Bool?

    /// Use `name` as the identifier
    var id: String { name }
}

// MARK: - AgentMode

enum AgentMode: String, Codable, Sendable {
    case subagent
    case primary
    case all
}

// MARK: - AgentPermissionEntry

struct AgentPermissionEntry: Codable, Sendable {
    let permission: String
    let action: String
    let pattern: String
}


// MARK: - AgentModel

struct AgentModel: Codable, Sendable {
    let modelID: String
    let providerID: String
}
