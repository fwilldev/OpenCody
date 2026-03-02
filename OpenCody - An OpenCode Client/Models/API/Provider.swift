import Foundation

// MARK: - Provider

/// Maps to `Provider` in types.gen.ts
struct Provider: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let source: ProviderSource
    let env: [String]
    let options: [String: AnyCodable]
    let models: [String: Model]
}

// MARK: - ProviderSource

enum ProviderSource: String, Codable, Sendable {
    case env
    case config
    case custom
    case api
}

// MARK: - Model

/// Maps to `Model` in types.gen.ts
struct Model: Codable, Identifiable, Sendable {
    let id: String
    let providerID: String
    let name: String
    let family: String?
    let api: ModelAPI
    let status: ModelStatus
    let capabilities: ModelCapabilities
    let cost: ModelCost
    let limit: ModelLimit
    let options: [String: AnyCodable]
    let headers: [String: String]
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, providerID, name, family, api, status, capabilities, cost, limit, options, headers
        case releaseDate = "release_date"
    }
}

struct ModelAPI: Codable, Sendable {
    let id: String
    let url: String?
    let npm: String
}

struct ModelCapabilities: Codable, Sendable {
    let temperature: Bool?
    let reasoning: Bool
    let attachment: Bool
    let toolcall: Bool
    /// `interleaved` can be `Bool` or `{field: String}` in the API — coerce dict to `true`.
    let interleaved: Bool
    let input: ModalityFlags
    let output: ModalityFlags

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try container.decodeIfPresent(Bool.self, forKey: .temperature)
        reasoning = try container.decode(Bool.self, forKey: .reasoning)
        attachment = try container.decode(Bool.self, forKey: .attachment)
        toolcall = try container.decode(Bool.self, forKey: .toolcall)
        input = try container.decode(ModalityFlags.self, forKey: .input)
        output = try container.decode(ModalityFlags.self, forKey: .output)
        // interleaved is Bool | {field: String} — treat any dict as `true`
        if let boolVal = try? container.decode(Bool.self, forKey: .interleaved) {
            interleaved = boolVal
        } else {
            // It's a dict (e.g. {field: "reasoning_content"}), treat as true
            interleaved = true
        }
    }

    enum CodingKeys: String, CodingKey {
        case temperature, reasoning, attachment, toolcall, interleaved, input, output
    }
}

struct ModalityFlags: Codable, Sendable {
    let text: Bool
    let audio: Bool
    let image: Bool
    let video: Bool
    let pdf: Bool
}

struct ModelCost: Codable, Sendable {
    let input: Double
    let output: Double
    let cache: ModelCostCache?
    let experimentalOver200K: ModelCostTier?

    enum CodingKeys: String, CodingKey {
        case input, output, cache
        case experimentalOver200K
    }
}

struct ModelCostCache: Codable, Sendable {
    let read: Double
    let write: Double
}

struct ModelCostTier: Codable, Sendable {
    let input: Double
    let output: Double
    let cache: ModelCostCache
}

struct ModelLimit: Codable, Sendable {
    let context: Int
    let output: Int
}

enum ModelStatus: String, Codable, Sendable {
    case alpha
    case beta
    case deprecated
    case active
}

// MARK: - ProviderAuthMethod

struct ProviderAuthMethod: Codable, Sendable {
    let type: ProviderAuthType
    let label: String
}

enum ProviderAuthType: String, Codable, Sendable {
    case oauth
    case api
}

// MARK: - ProviderAuthAuthorization

struct ProviderAuthAuthorization: Codable, Sendable {
    let url: String
    let method: ProviderAuthorizationMethod
    let instructions: String
}

enum ProviderAuthorizationMethod: String, Codable, Sendable {
    case auto
    case code
}
