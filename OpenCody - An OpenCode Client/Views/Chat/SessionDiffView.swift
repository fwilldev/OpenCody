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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
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

    private func loadDiff() async {
        isLoading = true
        error = nil
        do {
            let api = SessionAPI(client: apiClient)
            diffs = try await api.diff(id: session.id)
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
                // Render diff lines
                DiffContentView(before: diff.before, after: diff.after)
            }

            Divider()
                .overlay(Color.white.opacity(0.06))
        }
    }
}

// MARK: - DiffContentView

private struct DiffContentView: View {
    let before: String
    let after: String

    // Build unified diff line annotations by comparing before/after
    private var diffLines: [(line: String, kind: DiffLineKind)] {
        let afterLines = after.components(separatedBy: "\n")
        let beforeLines = before.components(separatedBy: "\n")
        let beforeSet = Set(beforeLines)
        let afterSet = Set(afterLines)

        var result: [(String, DiffLineKind)] = []
        // Removed lines
        for line in beforeLines where !afterSet.contains(line) {
            result.append(("-  " + line, .removed))
        }
        // Added lines
        for line in afterLines where !beforeSet.contains(line) {
            result.append(("+  " + line, .added))
        }
        // Context (unchanged): show a sample of after content
        if result.isEmpty {
            for line in afterLines.prefix(30) {
                result.append(("   " + line, .context))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
