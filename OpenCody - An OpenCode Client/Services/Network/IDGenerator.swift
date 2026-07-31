import Foundation

// MARK: - IDGenerator

/// Generates client-side identifiers for resources the server accepts IDs for.
///
/// Several endpoints let the client choose the ID of the entity it is creating —
/// `POST /session/{id}/message` accepts `messageID`, `/session/{id}/init` requires
/// one. The server validates only the prefix (`^msg`, `^prt`, …), so IDs are built
/// as `prefix_` + a monotonically increasing millisecond timestamp + random suffix.
/// The timestamp prefix keeps IDs sortable in creation order, matching the
/// server's own ascending-ID scheme.
enum IDGenerator {
    /// A new message identifier (`msg_…`).
    static func message() -> String { generate(prefix: "msg") }

    /// A new part identifier (`prt_…`).
    static func part() -> String { generate(prefix: "prt") }

    /// A new session identifier (`ses_…`).
    static func session() -> String { generate(prefix: "ses") }

    // MARK: - Private

    /// Base-36 encoded milliseconds since epoch, zero-padded so lexical order
    /// matches chronological order, followed by 8 random base-36 characters.
    private static func generate(prefix: String) -> String {
        let millis = UInt64(Date().timeIntervalSince1970 * 1000)
        let time = String(millis, radix: 36)
        let padded = String(repeating: "0", count: max(0, 9 - time.count)) + time
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let random = String((0..<8).map { _ in alphabet.randomElement() ?? "0" })
        return "\(prefix)_\(padded)\(random)"
    }
}
