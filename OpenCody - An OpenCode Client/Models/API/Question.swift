import Foundation

// MARK: - Question Models

/// Represents a request for user input from the assistant.
struct QuestionRequest: Codable, Identifiable, Sendable {
    let id: String
    let sessionID: String
    let questions: [QuestionInfo]
    let tool: QuestionToolRef?

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, questions, tool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID = (try? container.decodeIfPresent(String.self, forKey: .sessionID)) ?? ""
        questions = (try? container.decodeIfPresent([QuestionInfo].self, forKey: .questions)) ?? []
        tool = try? container.decodeIfPresent(QuestionToolRef.self, forKey: .tool)
    }
}

struct QuestionToolRef: Codable, Sendable {
    let messageID: String
    let callID: String
}

struct QuestionInfo: Codable, Sendable, Hashable {
    let question: String
    let header: String
    let options: [QuestionOption]
    let multiple: Bool?
    let custom: Bool?

    var allowsMultiple: Bool { multiple ?? false }
    var allowsCustom: Bool { custom ?? true }
}

struct QuestionOption: Codable, Sendable, Hashable {
    let label: String
    let description: String
}

/// A single question answer is an array of selected labels (or custom values).
typealias QuestionAnswer = [String]

// MARK: - SSE Payloads

struct QuestionRepliedPayload: Codable, Sendable {
    let sessionID: String
    let requestID: String
    let answers: [QuestionAnswer]
}

struct QuestionRejectedPayload: Codable, Sendable {
    let sessionID: String
    let requestID: String
}
