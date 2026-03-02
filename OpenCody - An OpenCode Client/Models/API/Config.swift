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
    var timeout: Int?
}

// MARK: - McpConfig

/// Local or Remote MCP server config, discriminated on `type`
enum McpConfig: Codable, Sendable {
    case local(McpLocalConfig)
    case remote(McpRemoteConfig)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
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
        }
    }
}

struct McpLocalConfig: Codable, Sendable {
    let type: String
    let command: [String]
    var environment: [String: String]?
    var enabled: Bool?
    var timeout: Int?
}

struct McpRemoteConfig: Codable, Sendable {
    let type: String
    let url: String
    var enabled: Bool?
    var headers: [String: String]?
    var timeout: Int?
}
