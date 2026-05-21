import Foundation

// MARK: - Question Models

/// Represents a request for user input from the assistant.
struct QuestionRequest: Decodable, Identifiable, Sendable {
    let id: String
    let sessionID: String
    let questions: [QuestionInfo]
    let tool: QuestionToolRef?

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case questions
        case tool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        questions = (try? container.decodeIfPresent([QuestionInfo].self, forKey: .questions)) ?? []
        tool = try? container.decodeIfPresent(QuestionToolRef.self, forKey: .tool)
    }
}

struct QuestionToolRef: Decodable, Sendable {
    let messageID: String
    let callID: String

    private enum CodingKeys: String, CodingKey {
        case messageID
        case messageIDCamel = "messageId"
        case messageIDSnake = "message_id"
        case callID
        case callIDCamel = "callId"
        case callIDSnake = "call_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageID =
            (try? container.decodeIfPresent(String.self, forKey: .messageID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .messageIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .messageIDSnake))
            ?? ""
        callID =
            (try? container.decodeIfPresent(String.self, forKey: .callID))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .callID)).map(String.init)
            ?? (try? container.decodeIfPresent(String.self, forKey: .callIDCamel))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .callIDCamel)).map(String.init)
            ?? (try? container.decodeIfPresent(String.self, forKey: .callIDSnake))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .callIDSnake)).map(String.init)
            ?? ""
    }
}

struct QuestionInfo: Decodable, Sendable, Hashable {
    let question: String
    let header: String
    let options: [QuestionOption]
    let multiple: Bool?
    let custom: Bool?

    var allowsMultiple: Bool { multiple ?? false }
    var allowsCustom: Bool { custom ?? true }
}

struct QuestionOption: Decodable, Sendable, Hashable {
    let label: String
    let description: String
}

/// A single question answer is an array of selected labels (or custom values).
typealias QuestionAnswer = [String]

// MARK: - SSE Payloads

struct QuestionRepliedPayload: Decodable, Sendable {
    let sessionID: String
    let requestID: String
    let answers: [QuestionAnswer]

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case requestID
        case requestIDCamel = "requestId"
        case requestIDSnake = "request_id"
        case answers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        requestID =
            (try? container.decodeIfPresent(String.self, forKey: .requestID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .requestIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .requestIDSnake))
            ?? ""
        answers = (try? container.decodeIfPresent([QuestionAnswer].self, forKey: .answers)) ?? []
    }
}

struct QuestionRejectedPayload: Decodable, Sendable {
    let sessionID: String
    let requestID: String

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case sessionIDCamel = "sessionId"
        case sessionIDSnake = "session_id"
        case requestID
        case requestIDCamel = "requestId"
        case requestIDSnake = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID =
            (try? container.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .sessionIDSnake))
            ?? ""
        requestID =
            (try? container.decodeIfPresent(String.self, forKey: .requestID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .requestIDCamel))
            ?? (try? container.decodeIfPresent(String.self, forKey: .requestIDSnake))
            ?? ""
    }
}
