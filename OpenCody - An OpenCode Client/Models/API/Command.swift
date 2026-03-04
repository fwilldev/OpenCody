import Foundation

// MARK: - Command

/// Maps to `Command.Info` in the opencode server.
/// The server schema includes `template` which may serialize as a string
/// or as an empty object (when it wraps a Promise). Custom decoding handles both.
struct SlashCommand: Codable, Identifiable, Sendable {
    let name: String
    let description: String?
    let agent: String?
    let model: String?
    let source: String?
    let template: String?
    let subtask: Bool?
    let hints: [String]

    /// Use `name` as the identifier
    var id: String { name }

    private enum CodingKeys: String, CodingKey {
        case name, description, agent, model, source, template, subtask, hints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        subtask = try container.decodeIfPresent(Bool.self, forKey: .subtask)
        hints = (try? container.decodeIfPresent([String].self, forKey: .hints)) ?? []
        // `template` may be a string or a serialized Promise (`{}`). Accept string, ignore object.
        if let str = try? container.decodeIfPresent(String.self, forKey: .template) {
            template = str
        } else {
            template = nil
        }
    }
}

// MARK: - ToolListItem

/// Maps to `ToolListItem` in types.gen.ts
struct ToolListItem: Codable, Identifiable, Sendable {
    let id: String
    let description: String
    let parameters: AnyCodable
}
