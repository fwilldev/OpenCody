import Foundation

// MARK: - SessionChangeSet

/// The file changes a session produced, aggregated across its user turns.
///
/// ## Why this exists
///
/// The obvious source — `GET /session/{id}/diff` — cannot produce a session-wide
/// diff. The server's handler begins with:
///
/// ```ts
/// if (!input.messageID) return []
/// ```
///
/// so calling it without a `messageID` always yields an empty array, and there is
/// no parameter that asks for "the whole session". Worse, `Session.summary` is
/// written as a hardcoded `{ additions: 0, deletions: 0, files: 0 }` and never
/// updated, and the `session.diff` SSE event is always published with `diff: []`.
/// Neither can be trusted (verified against opencode 1.18.9).
///
/// The real data is stored per user turn on `UserMessage.summary.diffs`, which the
/// client already receives from `GET /session/{id}/message`. This type assembles a
/// session-wide view from that, requiring no extra request.
///
/// ## Aggregation
///
/// Each turn's diff is *incremental* — the server computes it from the first
/// `step-start` snapshot to the last `step-finish` snapshot of that turn only — so
/// per-file addition and deletion counts are summed across turns. A file touched in
/// several turns keeps every turn's patch, concatenated in chronological order, which
/// `UnifiedDiff` renders as successive hunk groups.
struct SessionChangeSet: Sendable {
    /// One entry per changed file, in first-changed order.
    let files: [FileDiff]

    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    var fileCount: Int { files.count }
    var isEmpty: Bool { files.isEmpty }

    /// Build the change set from a session's messages.
    ///
    /// Only user messages carry diffs; assistant messages are ignored.
    init(messages: [MessageWithParts]) {
        // Preserve first-touched order while merging repeat edits to the same file.
        var order: [String] = []
        var merged: [String: FileDiff] = [:]

        for message in messages {
            guard case .user(let user) = message.message else { continue }
            for diff in user.summary?.diffs ?? [] {
                // A diff with no file path carries no renderable information.
                guard !diff.file.isEmpty else { continue }

                if let existing = merged[diff.file] {
                    merged[diff.file] = FileDiff(
                        file: existing.file,
                        patch: Self.concatenate(existing.patch, diff.patch),
                        additions: existing.additions + diff.additions,
                        deletions: existing.deletions + diff.deletions,
                        // A file added earlier and edited later is still, overall, added.
                        status: existing.status == .added ? .added : diff.status
                    )
                } else {
                    order.append(diff.file)
                    merged[diff.file] = diff
                }
            }
        }

        self.files = order.compactMap { merged[$0] }
    }

    /// Build a change set from already-resolved diffs (e.g. a single turn).
    init(files: [FileDiff]) {
        self.files = files
    }

    /// Join two patches for the same file, keeping either when the other is absent.
    private static func concatenate(_ first: String?, _ second: String?) -> String? {
        switch (first, second) {
        case (let a?, let b?):
            let separator = a.hasSuffix("\n") ? "" : "\n"
            return a + separator + b
        case (let a?, nil):
            return a
        case (nil, let b?):
            return b
        case (nil, nil):
            return nil
        }
    }
}

// MARK: - Session Summary Trust

extension SessionSummary {
    /// Whether this summary carries real numbers.
    ///
    /// The server initialises every session summary to `{0, 0, 0}` and never
    /// replaces it, so an all-zero summary means "not computed", not "no changes".
    /// Treating it as real would render a misleading `0 files · +0 -0`.
    var hasMeaningfulTotals: Bool {
        files > 0 || additions > 0 || deletions > 0
    }
}
