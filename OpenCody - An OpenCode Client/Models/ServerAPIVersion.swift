import Foundation

// MARK: - ServerAPIVersion

/// Which generation of the OpenCode server API a server speaks.
///
/// The two are not wire-compatible: OpenCode 2.x replaced the whole v1 REST surface
/// (`/session`, `/global/event`, …) with a new one under `/api/*`, a different message
/// model and an event-sourced stream. New servers default to `.v2` and the add-server
/// form detects the right one (`APIClient.detectAPIVersion`); servers saved before the
/// setting existed decode as `.v1`, which is what they ran.
nonisolated enum ServerAPIVersion: String, Codable, CaseIterable, Identifiable, Sendable {
    /// OpenCode 2.x (`@opencode/cli` on npm).
    case v2
    /// OpenCode 1.x (`opencode-ai` on npm).
    case v1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .v1: return "OpenCode 1.x"
        case .v2: return "OpenCode 2.x"
        }
    }
}
