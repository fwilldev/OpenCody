import Foundation

// MARK: - Command

/// Maps to `Command` in types.gen.ts
struct SlashCommand: Codable, Identifiable, Sendable {
    let name: String
    let description: String?
    let agent: String?
    let model: String?
    let template: String?
    let subtask: Bool?

    /// Use `name` as the identifier
    var id: String { name }
}

// MARK: - ToolListItem

/// Maps to `ToolListItem` in types.gen.ts
struct ToolListItem: Codable, Identifiable, Sendable {
    let id: String
    let description: String
    let parameters: AnyCodable
}
