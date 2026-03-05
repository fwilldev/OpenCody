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

    private func loadDiff() async {
        isLoading = true
        error = nil
        do {
            let api = SessionAPI(client: apiClient)
            #if DEBUG
            print("[SessionDiffView] loading diff for session=\(session.id)")
            #endif
            diffs = try await api.diff(id: session.id)
            #if DEBUG
            print("[SessionDiffView] loaded \(diffs.count) diffs")
            for d in diffs {
                print("[SessionDiffView]   file=\(d.file) status=\(d.status) +\(d.additions) -\(d.deletions)")
            }
            #endif
        } catch {
            #if DEBUG
            print("[SessionDiffView] ERROR: \(error)")
            #endif
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
                .overlay(Color.white.opacity(0.06))
        }
    }
}

// MARK: - DiffContentView

private struct DiffContentView: View {
    let diff: FileDiff

    // Build unified diff line annotations by comparing before/after
    private var diffLines: [(line: String, kind: DiffLineKind)] {
        switch diff.status {
        case .added:
            // Entire file is new — show all lines as added
            return diff.after.components(separatedBy: "\n").map { line in ("+  " + line, DiffLineKind.added) }
        case .deleted:
            // Entire file was removed — show all lines as removed
            return diff.before.components(separatedBy: "\n").map { line in ("-  " + line, DiffLineKind.removed) }
        case .modified:
            return buildModifiedDiff()
        }
    }

    private func buildModifiedDiff() -> [(String, DiffLineKind)] {
        let beforeLines = diff.before.components(separatedBy: "\n")
        let afterLines = diff.after.components(separatedBy: "\n")
        let beforeSet = Set(beforeLines)
        let afterSet = Set(afterLines)

        var result: [(String, DiffLineKind)] = []
        for line in beforeLines where !afterSet.contains(line) {
            result.append(("-  " + line, DiffLineKind.removed))
        }
        for line in afterLines where !beforeSet.contains(line) {
            result.append(("+  " + line, DiffLineKind.added))
        }
        return result
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diffLines.enumerated()), id: \.offset) { _, item in
                Text(item.line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(item.kind.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 1)
                    .background(item.kind.backgroundColor)
            }
        }
        .background(Theme.Colors.carbon)
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
    case added, removed, context

    var textColor: Color {
        switch self {
        case .added: return Theme.Colors.neonGreen
        case .removed: return Theme.Colors.hotPink
        case .context: return Theme.Colors.silver
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added: return Theme.Colors.neonGreen.opacity(0.07)
        case .removed: return Theme.Colors.hotPink.opacity(0.07)
        case .context: return Color.clear
        }
    }
}
