import Foundation

// MARK: - PermissionVariant

/// Which generation of the permission API a request came from.
///
/// The server exposes two parallel permission surfaces with identical semantics
/// but different key names and reply routes:
/// - `.v1` — `permission.asked` events / `GET /permission` / `POST /permission/{id}/reply`
/// - `.v2` — `permission.v2.asked` events / `GET /api/permission/request` /
///           `POST /api/session/{sessionID}/permission/request/{id}/reply`
enum PermissionVariant: String, Codable, Sendable {
    case v1
    case v2
}

// MARK: - Permission

/// A pending permission request from the assistant.
///
/// Maps to `PermissionRequest` (v1) and `PermissionV2Request` (v2). The two shapes
/// carry the same information under different key names, so decoding accepts both
/// and records which one matched in `variant`:
///
/// | meaning                      | v1          | v2          |
/// |------------------------------|-------------|-------------|
/// | what is being requested      | `permission`| `action`    |
/// | what it applies to           | `patterns`  | `resources` |
/// | persistable "always" targets | `always`    | `save`      |
/// | originating tool call        | `tool`      | `source`    |
struct Permission: Codable, Identifiable, Sendable {
    let id: String
    let sessionID: String

    /// The permission being requested — e.g. `"bash"`, `"edit"`, `"webfetch"`.
    /// Decoded from `permission` (v1) or `action` (v2).
    let permission: String

    /// Concrete targets the request applies to — e.g. a command string or file glob.
    /// Decoded from `patterns` (v1) or `resources` (v2).
    let patterns: [String]

    /// Targets for which an "always allow" decision can be persisted.
    /// Decoded from `always` (v1) or `save` (v2).
    let always: [String]

    let metadata: [String: AnyCodable]

    /// The tool call that triggered the request, when the server reports one.
    let tool: PermissionToolRef?

    /// Which API generation produced this request. Determines the reply route.
    let variant: PermissionVariant

    // MARK: Derived

    /// Human-readable label for the request — the server often puts a rendered
    /// title in `metadata.title`; otherwise fall back to the permission name.
    var displayTitle: String {
        if let title = metadata["title"]?.asString, !title.isEmpty {
            return title
        }
        return permission
    }

    /// First non-empty pattern — the common single-target case.
    var primaryPattern: String? {
        patterns.first(where: { !$0.isEmpty })
    }

    /// Whether an "always allow" reply is meaningful for this request.
    var supportsAlways: Bool { !always.isEmpty }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case sessionIDCamel = "sessionId"
        // v1
        case permission
        case patterns
        case always
        case tool
        // v2
        case action
        case resources
        case save
        case source
        // shared
        case metadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        sessionID =
            (try? c.decodeIfPresent(String.self, forKey: .sessionID))
            ?? (try? c.decodeIfPresent(String.self, forKey: .sessionIDCamel))
            ?? ""

        let v1Permission = try? c.decodeIfPresent(String.self, forKey: .permission)
        let v2Action = try? c.decodeIfPresent(String.self, forKey: .action)

        // v2 is identified by `action`/`resources`; anything else decodes as v1.
        if v1Permission == nil, v2Action != nil {
            variant = .v2
            permission = v2Action ?? ""
            patterns = (try? c.decodeIfPresent([String].self, forKey: .resources)) ?? []
            always = (try? c.decodeIfPresent([String].self, forKey: .save)) ?? []
            tool = try? c.decodeIfPresent(PermissionToolRef.self, forKey: .source)
        } else {
            variant = .v1
            permission = v1Permission ?? ""
            patterns = (try? c.decodeIfPresent([String].self, forKey: .patterns)) ?? []
            always = (try? c.decodeIfPresent([String].self, forKey: .always)) ?? []
            tool = try? c.decodeIfPresent(PermissionToolRef.self, forKey: .tool)
        }

        metadata = (try? c.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(metadata, forKey: .metadata)
        switch variant {
        case .v1:
            try c.encode(permission, forKey: .permission)
            try c.encode(patterns, forKey: .patterns)
            try c.encode(always, forKey: .always)
            try c.encodeIfPresent(tool, forKey: .tool)
        case .v2:
            try c.encode(permission, forKey: .action)
            try c.encode(patterns, forKey: .resources)
            try c.encode(always, forKey: .save)
            try c.encodeIfPresent(tool, forKey: .source)
        }
    }

    /// Memberwise initializer for previews and tests.
    init(
        id: String,
        sessionID: String,
        permission: String,
        patterns: [String] = [],
        always: [String] = [],
        metadata: [String: AnyCodable] = [:],
        tool: PermissionToolRef? = nil,
        variant: PermissionVariant = .v1
    ) {
        self.id = id
        self.sessionID = sessionID
        self.permission = permission
        self.patterns = patterns
        self.always = always
        self.metadata = metadata
        self.tool = tool
        self.variant = variant
    }
}

// MARK: - PermissionToolRef

/// The tool call a permission request originated from.
/// Maps to `PermissionRequest.tool` (v1) and `PermissionV2Source` (v2).
struct PermissionToolRef: Codable, Sendable {
    let messageID: String
    let callID: String

    private enum CodingKeys: String, CodingKey {
        case messageID
        case messageIDCamel = "messageId"
        case callID
        case callIDCamel = "callId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageID =
            (try? c.decodeIfPresent(String.self, forKey: .messageID))
            ?? (try? c.decodeIfPresent(String.self, forKey: .messageIDCamel))
            ?? ""
        callID =
            (try? c.decodeIfPresent(String.self, forKey: .callID))
            ?? (try? c.decodeIfPresent(String.self, forKey: .callIDCamel))
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(messageID, forKey: .messageID)
        try c.encode(callID, forKey: .callID)
    }

    init(messageID: String, callID: String) {
        self.messageID = messageID
        self.callID = callID
    }
}

// MARK: - PermissionReplyDecision

/// The three possible answers to a permission request.
/// Maps to the `reply` field of `POST /permission/{requestID}/reply`.
enum PermissionReplyDecision: String, Codable, Sendable {
    /// Allow this one occurrence.
    case once
    /// Allow and persist the decision for the matching patterns.
    case always
    /// Deny the request.
    case reject
}

// MARK: - PermissionSavedInfo

/// A persisted "always allow" decision. Maps to `PermissionSavedInfo`.
struct PermissionSavedInfo: Codable, Identifiable, Sendable {
    let id: String
    let projectID: String
    let action: String
    let resource: String
}
