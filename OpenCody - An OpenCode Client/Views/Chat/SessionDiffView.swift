//
//  SessionDiffView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Full-screen sheet showing the diff for the current session.
/// Added lines shown with neonGreen background, removed with hotPink.
struct SessionDiffView: View {
    let session: Session
    let apiClient: APIClient
    let showsCloseButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var diffs: [FileDiff] = []
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading diff…")
                        .tint(Theme.Colors.cyberBlue)
                        .foregroundStyle(Theme.Colors.silver)
                } else if let err = error {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(Theme.Colors.hotPink)
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.silver)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if diffs.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.rectangle",
                        title: "No Changes",
                        message: "This session has no file diffs yet."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(diffs, id: \.file) { diff in
                                FileDiffSection(diff: diff)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Session Diff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(Theme.Colors.silver)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Text("\(diffs.count) file\(diffs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .task {
            await loadDiff()
        }
    }

    init(session: Session, apiClient: APIClient, showsCloseButton: Bool = true) {
        self.session = session
        self.apiClient = apiClient
        self.showsCloseButton = showsCloseButton
    }

    /// Load the session's changes.
    ///
    /// Built from `UserMessage.summary.diffs` rather than `GET /session/{id}/diff`:
    /// that endpoint returns `[]` unless a `messageID` is supplied and has no
    /// whole-session mode, so it cannot answer "what did this session change".
    /// See `SessionChangeSet` for the details.
    private func loadDiff() async {
        isLoading = true
        error = nil
        do {
            let api = MessageAPI(client: apiClient, directory: session.directory)
            let responses = try await api.list(sessionID: session.id)
            let changeSet = SessionChangeSet(messages: responses.map { $0.toModel() })
            diffs = changeSet.files
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - FileDiffSection

private struct FileDiffSection: View {
    let diff: FileDiff
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.silver)
                    Text(diff.file)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Theme.Colors.cloud)
                        .lineLimit(1)
                    Spacer()
                    Text(diff.status.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(diff.status.color)
                    HStack(spacing: 6) {
                        Text("+\(diff.additions)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.Colors.neonGreen)
                        Text("-\(diff.deletions)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.Colors.hotPink)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .background(Theme.Colors.graphite)
            }
            .buttonStyle(.plain)

            if isExpanded {
                if diff.additions + diff.deletions > 5000 {
                    Text("Too many changes to display (\(diff.additions + diff.deletions) lines)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.smoke)
                        .padding(Theme.Spacing.md)
                } else {
                    DiffContentView(diff: diff)
                }
            }

            Divider()
                .overlay(Theme.Colors.hairline)
        }
    }
}

// MARK: - DiffContentView

private struct DiffContentView: View {
    let diff: FileDiff

    /// Renderable lines parsed from the server's unified-diff patch.
    private var lines: [UnifiedDiff.Line] { diff.parsedDiff.lines }

    var body: some View {
        if lines.isEmpty {
            // No patch text — e.g. a binary file or a summary-only diff entry.
            Text(
                diff.additions + diff.deletions > 0
                    ? "\(diff.additions + diff.deletions) changed lines — no preview available"
                    : "No textual changes"
            )
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.Colors.smoke)
            .padding(Theme.Spacing.md)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    DiffLineRow(line: line)
                }
            }
            .background(Theme.Colors.carbon)
        }
    }
}

// MARK: - DiffLineRow

private struct DiffLineRow: View {
    let line: UnifiedDiff.Line

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(gutter)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.Colors.smoke)
                .frame(width: 34, alignment: .trailing)

            Text(marker + line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(kind.textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 1)
        .background(kind.backgroundColor)
    }

    /// Line number shown in the gutter — new-file number, falling back to the old one.
    private var gutter: String {
        if line.kind == .header { return "" }
        if let n = line.newLineNumber { return String(n) }
        if let o = line.oldLineNumber { return String(o) }
        return ""
    }

    private var marker: String {
        switch line.kind {
        case .added: return "+ "
        case .removed: return "- "
        case .context: return "  "
        case .header: return ""
        }
    }

    private var kind: DiffLineKind {
        switch line.kind {
        case .added: return .added
        case .removed: return .removed
        case .context: return .context
        case .header: return .header
        }
    }
}

// MARK: - FileDiffStatus + Color

extension FileDiffStatus {
    var color: Color {
        switch self {
        case .modified: return Theme.Colors.cyberBlue
        case .added: return Theme.Colors.neonGreen
        case .deleted: return Theme.Colors.hotPink
        }
    }
}

private enum DiffLineKind {
    case added, removed, context, header

    var textColor: Color {
        switch self {
        case .added: return Theme.Colors.neonGreen
        case .removed: return Theme.Colors.hotPink
        case .context: return Theme.Colors.silver
        case .header: return Theme.Colors.cyberBlue
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added: return Theme.Colors.neonGreen.opacity(0.07)
        case .removed: return Theme.Colors.hotPink.opacity(0.07)
        case .context: return Color.clear
        case .header: return Theme.Colors.cyberBlue.opacity(0.08)
        }
    }
}
