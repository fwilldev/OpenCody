import Foundation

// MARK: - Config

/// Maps to `Config` in types.gen.ts.
/// All fields optional to support partial GET/PATCH semantics.
struct ServerConfig: Codable, Sendable {
    var schema: String?
    var theme: String?
    var keybinds: KeybindsConfig?
    var logLevel: String?
    var tui: TuiConfig?
    var command: [String: CommandConfig]?
    var watcher: WatcherConfig?
    var plugin: [String]?
    var snapshot: Bool?
    var share: String?
    var autoshare: Bool?
    var autoupdate: AutoupdateValue?
    var disabledProviders: [String]?
    var enabledProviders: [String]?
    var model: String?
    var smallModel: String?
    var username: String?
    var agent: [String: AgentConfig]?
    var provider: [String: ProviderConfig]?
    var mcp: [String: McpConfig]?
    var instructions: [String]?
    var layout: String?

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case theme
        case keybinds
        case logLevel
        case tui
        case command
        case watcher
        case plugin
        case snapshot
        case share
        case autoshare
        case autoupdate
        case disabledProviders = "disabled_providers"
        case enabledProviders = "enabled_providers"
        case model
        case smallModel = "small_model"
        case username
        case agent
        case provider
        case mcp
        case instructions
        case layout
    }
}

// MARK: - AutoupdateValue

/// Can be `true`, `false`, or `"notify"`
enum AutoupdateValue: Codable, Sendable {
    case bool(Bool)
    case notify

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let s = try? container.decode(String.self), s == "notify" {
            self = .notify
        } else {
            self = .bool(false)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try container.encode(b)
        case .notify: try container.encode("notify")
        }
    }
}

// MARK: - KeybindsConfig

struct KeybindsConfig: Codable, Sendable {
    var leader: String?
    var appExit: String?
    var editorOpen: String?
    var themeList: String?
    var sidebarToggle: String?
    var scrollbarToggle: String?
    var usernameToggle: String?
    var statusView: String?
    var sessionExport: String?
    var sessionNew: String?
    var sessionList: String?
    var sessionTimeline: String?
    var sessionShare: String?
    var sessionUnshare: String?
    var sessionInterrupt: String?
    var sessionCompact: String?
    var messagesPageUp: String?
    var messagesPageDown: String?
    var messagesLineUp: String?
    var messagesLineDown: String?
    var messagesHalfPageUp: String?
    var messagesHalfPageDown: String?
    var messagesFirst: String?
    var messagesLast: String?
    var messagesNext: String?
    var messagesPrevious: String?
    var messagesLastUser: String?
    var messagesCopy: String?
    var messagesUndo: String?
    var messagesRedo: String?
    var messagesToggleConceal: String?
    var toolDetails: String?
    var modelList: String?
    var modelCycleRecent: String?
    var modelCycleRecentReverse: String?
    var commandList: String?
    var agentList: String?
    var agentCycle: String?
    var agentCycleReverse: String?
    var inputClear: String?
    var inputForwardDelete: String?
    var inputPaste: String?
    var inputSubmit: String?
    var inputNewline: String?
    var historyPrevious: String?
    var historyNext: String?
    var sessionChildCycle: String?
    var sessionChildCycleReverse: String?
    var terminalSuspend: String?
    var terminalTitleToggle: String?

    enum CodingKeys: String, CodingKey {
        case leader
        case appExit = "app_exit"
        case editorOpen = "editor_open"
        case themeList = "theme_list"
        case sidebarToggle = "sidebar_toggle"
        case scrollbarToggle = "scrollbar_toggle"
        case usernameToggle = "username_toggle"
        case statusView = "status_view"
        case sessionExport = "session_export"
        case sessionNew = "session_new"
        case sessionList = "session_list"
        case sessionTimeline = "session_timeline"
        case sessionShare = "session_share"
        case sessionUnshare = "session_unshare"
        case sessionInterrupt = "session_interrupt"
        case sessionCompact = "session_compact"
        case messagesPageUp = "messages_page_up"
        case messagesPageDown = "messages_page_down"
        case messagesLineUp = "messages_line_up"
        case messagesLineDown = "messages_line_down"
        case messagesHalfPageUp = "messages_half_page_up"
        case messagesHalfPageDown = "messages_half_page_down"
        case messagesFirst = "messages_first"
        case messagesLast = "messages_last"
        case messagesNext = "messages_next"
        case messagesPrevious = "messages_previous"
        case messagesLastUser = "messages_last_user"
        case messagesCopy = "messages_copy"
        case messagesUndo = "messages_undo"
        case messagesRedo = "messages_redo"
        case messagesToggleConceal = "messages_toggle_conceal"
        case toolDetails = "tool_details"
        case modelList = "model_list"
        case modelCycleRecent = "model_cycle_recent"
        case modelCycleRecentReverse = "model_cycle_recent_reverse"
        case commandList = "command_list"
        case agentList = "agent_list"
        case agentCycle = "agent_cycle"
        case agentCycleReverse = "agent_cycle_reverse"
        case inputClear = "input_clear"
        case inputForwardDelete = "input_forward_delete"
        case inputPaste = "input_paste"
        case inputSubmit = "input_submit"
        case inputNewline = "input_newline"
        case historyPrevious = "history_previous"
        case historyNext = "history_next"
        case sessionChildCycle = "session_child_cycle"
        case sessionChildCycleReverse = "session_child_cycle_reverse"
        case terminalSuspend = "terminal_suspend"
        case terminalTitleToggle = "terminal_title_toggle"
    }
}

// MARK: - TuiConfig

struct TuiConfig: Codable, Sendable {
    var scrollSpeed: Int?
    var scrollAcceleration: ScrollAccelerationConfig?
    var diffStyle: String?

    enum CodingKeys: String, CodingKey {
        case scrollSpeed = "scroll_speed"
        case scrollAcceleration = "scroll_acceleration"
        case diffStyle = "diff_style"
    }
}

struct ScrollAccelerationConfig: Codable, Sendable {
    let enabled: Bool
}

// MARK: - CommandConfig

struct CommandConfig: Codable, Sendable {
    let template: String
    var description: String?
    var agent: String?
    var model: String?
    var subtask: Bool?
}

// MARK: - WatcherConfig

struct WatcherConfig: Codable, Sendable {
    var ignore: [String]?
}

// MARK: - AgentConfig

struct AgentConfig: Codable, Sendable {
    var model: String?
    var temperature: Double?
    var topP: Double?
    var prompt: String?
    var tools: [String: Bool]?
    var disable: Bool?
    var description: String?
    var mode: String?
    var color: String?
    var maxSteps: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case topP = "top_p"
        case prompt
        case tools
        case disable
        case description
        case mode
        case color
        case maxSteps
    }
}

// MARK: - ProviderConfig

struct ProviderConfig: Codable, Sendable {
    var api: String?
    var name: String?
    var env: [String]?
    var id: String?
    var npm: String?
    var models: [String: ProviderModelConfig]?
    var whitelist: [String]?
    var blacklist: [String]?
    var options: ProviderOptions?
}

struct ProviderModelConfig: Codable, Sendable {
    var id: String?
    var name: String?
    var releaseDate: String?
    var attachment: Bool?
    var reasoning: Bool?
    var temperature: Bool?
    var toolCall: Bool?
    var cost: ProviderModelCost?
    var limit: ProviderModelLimit?
    var experimental: Bool?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case releaseDate = "release_date"
        case attachment, reasoning, temperature
        case toolCall = "tool_call"
        case cost, limit, experimental, status
    }
}

struct ProviderModelCost: Codable, Sendable {
    let input: Double
    let output: Double
    var cacheRead: Double?
    var cacheWrite: Double?

    enum CodingKeys: String, CodingKey {
        case input, output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

struct ProviderModelLimit: Codable, Sendable {
    let context: Int
    let output: Int
}

struct ProviderOptions: Codable, Sendable {
    var apiKey: String?
    var baseURL: String?
    var enterpriseUrl: String?
    var setCacheKey: Bool?
    /// Request timeout in ms. The server also accepts `false` (no timeout), which
    /// decodes as `nil` rather than failing the whole config.
    var timeout: Int?

    private enum CodingKeys: String, CodingKey {
        case apiKey, baseURL, enterpriseUrl, setCacheKey, timeout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try? c.decodeIfPresent(String.self, forKey: .apiKey)
        baseURL = try? c.decodeIfPresent(String.self, forKey: .baseURL)
        enterpriseUrl = try? c.decodeIfPresent(String.self, forKey: .enterpriseUrl)
        setCacheKey = try? c.decodeIfPresent(Bool.self, forKey: .setCacheKey)
        timeout = try? c.decodeIfPresent(Int.self, forKey: .timeout)
    }
}

// MARK: - McpConfig

/// One entry of the config's `mcp` map.
///
/// The server models this as `McpLocalConfig | McpRemoteConfig | { enabled: Bool }`.
/// That third variant is easy to miss and matters a lot: it is how a config file
/// enables or disables a server that is *defined somewhere else* in the config
/// chain, and it carries no `type`. Treating it as a decode failure takes the whole
/// `GET /config` response down with it, not just the one entry.
enum McpConfig: Codable, Sendable {
    case local(McpLocalConfig)
    case remote(McpRemoteConfig)
    /// `{ "enabled": Bool }` — an enable/disable override for a server declared elsewhere.
    case enabledOverride(Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // The override variant has no `type`, so probe for it first.
        guard let type = try container.decodeIfPresent(String.self, forKey: .type) else {
            let enabled = try container.decode(Bool.self, forKey: .enabled)
            self = .enabledOverride(enabled)
            return
        }

        switch type {
        case "local":
            self = .local(try McpLocalConfig(from: decoder))
        case "remote":
            self = .remote(try McpRemoteConfig(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown MCP config type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .local(let c): try c.encode(to: encoder)
        case .remote(let c): try c.encode(to: encoder)
        case .enabledOverride(let enabled):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enabled, forKey: .enabled)
        }
    }

    // MARK: - Accessors

    /// Whether the server is enabled. An entry with no explicit flag counts as enabled.
    var isEnabled: Bool {
        switch self {
        case .local(let c): return c.enabled ?? true
        case .remote(let c): return c.enabled ?? true
        case .enabledOverride(let enabled): return enabled
        }
    }

    /// A one-line summary of what this server connects to, for list rows.
    ///
    /// `nil` for an override entry: it carries no connection details, and repeating
    /// its enabled flag would just duplicate the status line next to it.
    var summary: String? {
        switch self {
        case .local(let c): return c.command.joined(separator: " ")
        case .remote(let c): return c.url
        case .enabledOverride: return nil
        }
    }

    /// The same entry with `enabled` set — used to toggle a server persistently.
    func settingEnabled(_ enabled: Bool) -> McpConfig {
        switch self {
        case .local(var c):
            c.enabled = enabled
            return .local(c)
        case .remote(var c):
            c.enabled = enabled
            return .remote(c)
        case .enabledOverride:
            return .enabledOverride(enabled)
        }
    }
}

// MARK: - McpLocalConfig

/// A stdio MCP server: a process the opencode server spawns and talks to over stdin/stdout.
struct McpLocalConfig: Codable, Sendable {
    let type: String
    /// Command and arguments, already split into argv form.
    var command: [String]
    /// Working directory for the process. Relative paths resolve from the workspace.
    var cwd: String?
    var environment: [String: String]?
    var enabled: Bool?
    /// Request timeout in ms. The server defaults to 5000 when absent.
    var timeout: Int?

    init(
        command: [String],
        cwd: String? = nil,
        environment: [String: String]? = nil,
        enabled: Bool? = nil,
        timeout: Int? = nil
    ) {
        self.type = "local"
        self.command = command
        self.cwd = cwd
        self.environment = environment
        self.enabled = enabled
        self.timeout = timeout
    }
}

// MARK: - McpRemoteConfig

/// A remote MCP server reached over HTTP (streamable HTTP or SSE).
struct McpRemoteConfig: Codable, Sendable {
    let type: String
    var url: String
    var enabled: Bool?
    /// Static headers sent with every request — the usual home for a bearer token.
    var headers: [String: String]?
    /// OAuth settings, or `.disabled` to switch off the server's OAuth auto-detection.
    var oauth: McpOAuthSetting?
    var timeout: Int?

    init(
        url: String,
        enabled: Bool? = nil,
        headers: [String: String]? = nil,
        oauth: McpOAuthSetting? = nil,
        timeout: Int? = nil
    ) {
        self.type = "remote"
        self.url = url
        self.enabled = enabled
        self.headers = headers
        self.oauth = oauth
        self.timeout = timeout
    }
}

// MARK: - McpOAuthSetting

/// `oauth` on a remote MCP server: either a config object, or literal `false` to
/// suppress the server's OAuth auto-discovery entirely.
enum McpOAuthSetting: Codable, Sendable {
    case disabled
    case settings(McpOAuthConfig)

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let flag = try? single.decode(Bool.self) {
            // Only `false` is meaningful here; `true` is not part of the server's union.
            self = flag ? .settings(McpOAuthConfig()) : .disabled
            return
        }
        self = .settings(try McpOAuthConfig(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .disabled:
            var single = encoder.singleValueContainer()
            try single.encode(false)
        case .settings(let config):
            try config.encode(to: encoder)
        }
    }
}

struct McpOAuthConfig: Codable, Sendable {
    /// Omit to let the server attempt dynamic client registration (RFC 7591).
    var clientId: String?
    var clientSecret: String?
    var scope: String?
    var callbackPort: Int?
    var redirectUri: String?

    init(
        clientId: String? = nil,
        clientSecret: String? = nil,
        scope: String? = nil,
        callbackPort: Int? = nil,
        redirectUri: String? = nil
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.scope = scope
        self.callbackPort = callbackPort
        self.redirectUri = redirectUri
    }
}
