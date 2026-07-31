import Foundation

// MARK: - UnifiedDiff

/// A parsed unified-diff patch.
///
/// The server delivers per-file changes as unified diff text (`FileDiff.patch`,
/// `VcsFileDiff.patch`, `POST /vcs/diff/raw`). This parses that text into hunks of
/// annotated lines so views can render additions and deletions without having to
/// reconstruct them from full before/after contents.
struct UnifiedDiff: Sendable {
    let hunks: [Hunk]

    /// Every line across all hunks, with a separator entry between hunks.
    var lines: [Line] { hunks.flatMap(\.displayLines) }

    var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count } }
    var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count } }

    var isEmpty: Bool { hunks.isEmpty }

    // MARK: - Nested Types

    /// What a diff line represents.
    enum LineKind: Sendable, Equatable {
        case added
        case removed
        case context
        /// A `@@ … @@` hunk header.
        case header
    }

    struct Line: Sendable, Identifiable, Equatable {
        /// Stable index within the parsed diff, used as the SwiftUI identity.
        let id: Int
        let kind: LineKind
        /// Line content without the leading `+`/`-`/space marker.
        let text: String
        /// 1-based line number in the original file, when the line exists there.
        let oldLineNumber: Int?
        /// 1-based line number in the new file, when the line exists there.
        let newLineNumber: Int?
    }

    struct Hunk: Sendable {
        let header: String
        let oldStart: Int
        let newStart: Int
        let lines: [Line]

        /// Hunk header followed by its lines.
        var displayLines: [Line] {
            guard !header.isEmpty else { return lines }
            return [Line(id: (lines.first?.id ?? 0) - 1, kind: .header, text: header, oldLineNumber: nil, newLineNumber: nil)] + lines
        }
    }

    // MARK: - Parsing

    /// Parse unified diff text.
    ///
    /// Tolerates patches with or without `---`/`+++` file headers and ignores
    /// `diff --git`, `index`, and other extended-header lines. A patch with no
    /// recognizable `@@` hunk header is treated as a single implicit hunk so that
    /// bare diff bodies still render.
    init(patch: String) {
        var hunks: [Hunk] = []
        var currentHeader = ""
        var currentLines: [Line] = []
        var currentOldStart = 0
        var currentNewStart = 0
        var oldCursor = 0
        var newCursor = 0
        var lineID = 0
        var sawHunkHeader = false

        func flush() {
            guard !currentLines.isEmpty || !currentHeader.isEmpty else { return }
            hunks.append(
                Hunk(
                    header: currentHeader,
                    oldStart: currentOldStart,
                    newStart: currentNewStart,
                    lines: currentLines
                )
            )
            currentHeader = ""
            currentLines = []
        }

        for raw in patch.components(separatedBy: "\n") {
            if raw.hasPrefix("@@") {
                flush()
                sawHunkHeader = true
                currentHeader = raw
                let ranges = Self.parseHunkRanges(raw)
                currentOldStart = ranges.oldStart
                currentNewStart = ranges.newStart
                oldCursor = ranges.oldStart
                newCursor = ranges.newStart
                continue
            }

            // Skip extended headers — but only before the first hunk, since a
            // context line inside a hunk can legitimately start with these.
            if !sawHunkHeader {
                if raw.hasPrefix("diff ") || raw.hasPrefix("index ")
                    || raw.hasPrefix("--- ") || raw.hasPrefix("+++ ")
                    || raw.hasPrefix("old mode") || raw.hasPrefix("new mode")
                    || raw.hasPrefix("similarity index") || raw.hasPrefix("rename ")
                    || raw.hasPrefix("deleted file mode") || raw.hasPrefix("new file mode")
                    || raw.hasPrefix("Binary files") {
                    continue
                }
            } else if raw.hasPrefix("--- ") || raw.hasPrefix("+++ ") || raw.hasPrefix("diff --git") {
                // A new file section inside a multi-file patch.
                flush()
                sawHunkHeader = false
                continue
            }

            // `\ No newline at end of file` is metadata, not content.
            if raw.hasPrefix("\\") { continue }

            let kind: LineKind
            let text: String
            var oldNumber: Int?
            var newNumber: Int?

            if raw.hasPrefix("+") {
                kind = .added
                text = String(raw.dropFirst())
                newNumber = newCursor
                newCursor += 1
            } else if raw.hasPrefix("-") {
                kind = .removed
                text = String(raw.dropFirst())
                oldNumber = oldCursor
                oldCursor += 1
            } else {
                // Context line — a leading space, or an empty trailing line.
                if raw.isEmpty && currentLines.isEmpty && !sawHunkHeader { continue }
                kind = .context
                text = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
                oldNumber = oldCursor
                newNumber = newCursor
                oldCursor += 1
                newCursor += 1
            }

            currentLines.append(
                Line(id: lineID, kind: kind, text: text, oldLineNumber: oldNumber, newLineNumber: newNumber)
            )
            lineID += 1
        }

        flush()

        // Drop a trailing all-empty implicit hunk produced by a trailing newline.
        self.hunks = hunks.filter { !$0.lines.isEmpty || !$0.header.isEmpty }
    }

    /// Extract the `oldStart` / `newStart` line numbers from a `@@ -a,b +c,d @@` header.
    private static func parseHunkRanges(_ header: String) -> (oldStart: Int, newStart: Int) {
        // Format: @@ -oldStart[,oldCount] +newStart[,newCount] @@ optional section heading
        var oldStart = 1
        var newStart = 1
        let parts = header.split(separator: " ")
        for part in parts {
            if part.hasPrefix("-") {
                let digits = part.dropFirst().split(separator: ",").first ?? ""
                oldStart = Int(digits) ?? 1
            } else if part.hasPrefix("+") {
                let digits = part.dropFirst().split(separator: ",").first ?? ""
                newStart = Int(digits) ?? 1
            }
        }
        return (oldStart, newStart)
    }
}

// MARK: - FileDiff Convenience

extension FileDiff {
    /// The patch parsed into renderable diff lines.
    ///
    /// When the server sent no patch (e.g. a binary file, or a summary-only diff)
    /// the result is empty and callers should fall back to the add/remove counts.
    var parsedDiff: UnifiedDiff {
        UnifiedDiff(patch: patch ?? "")
    }

    /// File name without directories, for compact display.
    var fileName: String {
        (file as NSString).lastPathComponent
    }
}
