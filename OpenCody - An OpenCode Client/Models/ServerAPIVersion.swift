import Foundation

// MARK: - ServerAPIVersion

/// Which generation of the OpenCode server API a server speaks.
///
/// The two are not wire-compatible: OpenCode 2.x replaced the whole v1 REST surface
/// (`/session`, `/global/event`, …) with a new one under `/api/*`, a different message
/// model and an event-sourced stream. The server does not advertise which one it runs
/// in a way both generations answer, so the user picks it per server. `.v1` is the
/// default because it is what every server configured before this setting existed runs.
nonisolated enum ServerAPIVersion: String, Codable, CaseIterable, Identifiable, Sendable {
    /// OpenCode 1.x (`opencode-ai` on npm).
    case v1
    /// OpenCode 2.x (`@opencode/cli` on npm).
    case v2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .v1: return "OpenCode 1.x"
        case .v2: return "OpenCode 2.x"
        }
    }
}
