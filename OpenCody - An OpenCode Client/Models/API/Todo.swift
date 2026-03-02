import Foundation

// MARK: - TodoItem

/// Maps to `Todo` in types.gen.ts
struct TodoItem: Codable, Identifiable, Sendable {
    let content: String
    let status: TodoStatus
    let priority: TodoPriority

    /// Synthesized stable identifier — not returned by the API.
    var id: String { content }

}

// MARK: - TodoStatus

enum TodoStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

// MARK: - TodoPriority

enum TodoPriority: String, Codable, Sendable {
    case high
    case medium
    case low
}

// MARK: - TodoList

/// Convenience wrapper for a list of todos
struct TodoList: Codable, Sendable {
    let sessionID: String
    let items: [TodoItem]

    enum CodingKeys: String, CodingKey {
        case sessionID
        case items = "todos"
    }
}
