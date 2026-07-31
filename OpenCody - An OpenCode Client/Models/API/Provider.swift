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
    /// Named request variants (e.g. reasoning-effort tiers) the model supports.
    let variants: [String: AnyCodable]?

    /// Variant identifiers this model accepts, sorted for stable display.
    var variantIDs: [String] { (variants ?? [:]).keys.sorted() }

    enum CodingKeys: String, CodingKey {
        case id, providerID, name, family, api, status, capabilities, cost, limit, options, headers, variants
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
    /// Context-size pricing tiers, when the provider charges by context length.
    let tiers: [ModelCostTierEntry]?
    let experimentalOver200K: ModelCostTier?

    enum CodingKeys: String, CodingKey {
        case input, output, cache, tiers
        case experimentalOver200K
    }
}

/// One entry of `ModelCost.tiers` — pricing that applies above a context threshold.
struct ModelCostTierEntry: Codable, Sendable {
    let input: Double
    let output: Double
    let cache: ModelCostCache?
    let tier: Threshold?

    struct Threshold: Codable, Sendable {
        /// Currently always `"context"`.
        let type: String
        /// Context size in tokens at which this tier starts applying.
        let size: Double
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
    /// Maximum input tokens, when the provider states one separately from `context`.
    let input: Int?
}

enum ModelStatus: String, Codable, Sendable {
    case alpha
    case beta
    case deprecated
    case active
}

// MARK: - ProviderAuthMethod

/// One way to authenticate with a provider.
///
/// The **index** of a method within a provider's method array is its identifier
/// for `POST /provider/{id}/oauth/authorize` and `…/callback`.
struct ProviderAuthMethod: Codable, Sendable {
    let type: ProviderAuthType
    let label: String
    /// Inputs the client must collect before starting the flow (API key, region, …).
    let prompts: [ProviderAuthPrompt]?

    /// Prompts that should be shown given the values collected so far, honouring
    /// each prompt's `when` condition.
    func visiblePrompts(given values: [String: String]) -> [ProviderAuthPrompt] {
        (prompts ?? []).filter { $0.isVisible(given: values) }
    }
}

enum ProviderAuthType: String, Codable, Sendable {
    case oauth
    case api
}

// MARK: - ProviderAuthPrompt

/// A single input the user must supply during an auth flow.
/// Maps to the `prompts` union of `ProviderAuthMethod`.
struct ProviderAuthPrompt: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case text
        case select
    }

    let type: Kind
    let key: String
    let message: String
    let placeholder: String?
    /// Choices, present when `type == .select`.
    let options: [Option]?
    /// Condition gating whether this prompt applies.
    let when: Condition?

    var id: String { key }

    struct Option: Codable, Sendable, Identifiable, Hashable {
        let label: String
        let value: String
        let hint: String?

        var id: String { value }
    }

    /// `{ key, op, value }` — show this prompt only when another answer matches.
    struct Condition: Codable, Sendable {
        enum Op: String, Codable, Sendable {
            case eq
            case neq
        }

        let key: String
        let op: Op
        let value: String

        /// Evaluate the condition against previously collected answers.
        func matches(_ values: [String: String]) -> Bool {
            let actual = values[key]
            switch op {
            case .eq: return actual == value
            case .neq: return actual != value
            }
        }
    }

    /// Whether this prompt should be shown given the answers collected so far.
    func isVisible(given values: [String: String]) -> Bool {
        guard let when else { return true }
        return when.matches(values)
    }
}

// MARK: - ProviderAuthAuthorization

/// Result of starting an auth flow.
struct ProviderAuthAuthorization: Codable, Sendable {
    /// URL the user must open to authorize.
    let url: String
    /// `.auto` completes without further input; `.code` requires posting a code back.
    let method: ProviderAuthorizationMethod
    let instructions: String
}

enum ProviderAuthorizationMethod: String, Codable, Sendable {
    case auto
    case code
}

// MARK: - ProviderCredential

/// A credential written to the server's auth store via `PUT /auth/{providerID}`.
/// Maps to the `Auth` union (`OAuth | ApiAuth | WellKnownAuth`).
enum ProviderCredential: Encodable, Sendable {
    case oauth(access: String, refresh: String, expires: Int)
    case api(key: String, metadata: [String: String]?)
    case wellKnown(key: String, token: String)

    private enum CodingKeys: String, CodingKey {
        case type, refresh, access, expires, key, metadata, token
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .oauth(let access, let refresh, let expires):
            try c.encode("oauth", forKey: .type)
            try c.encode(access, forKey: .access)
            try c.encode(refresh, forKey: .refresh)
            try c.encode(expires, forKey: .expires)
        case .api(let key, let metadata):
            try c.encode("api", forKey: .type)
            try c.encode(key, forKey: .key)
            try c.encodeIfPresent(metadata, forKey: .metadata)
        case .wellKnown(let key, let token):
            try c.encode("wellknown", forKey: .type)
            try c.encode(key, forKey: .key)
            try c.encode(token, forKey: .token)
        }
    }
}
