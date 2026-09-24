//
//  FileMentionPaletteView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Floating overlay shown above the chat input when the user types "@".
/// Searches files via `GET /find/file`, filters in real-time, and calls back
/// with the selected file path.
struct FileMentionPaletteView: View {
    let apiClient: APIClient
    /// The project directory for scoping the file search.
    let directory: String?
    /// The query after the "@" trigger (e.g. "" or ".swift" or "Chat").
    let query: String
    /// Called with the relative file path when the user selects a file.
    let onSelect: (String) -> Void
    /// Called when the palette should be dismissed without a selection.
    let onDismiss: () -> Void

    @State private var results: [String] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.neonOrange)
                Text("File Reference")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.neonOrange)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(Theme.Colors.graphite)

            Divider()
                .overlay(Theme.Colors.border)

            // Content area
            if isLoading && results.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Theme.Colors.cyberBlue)
                    Text("Searching files…")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
                .padding(Theme.Spacing.md)
            } else if let err = loadError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.hotPink)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
                .padding(Theme.Spacing.md)
            } else if results.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                    Text(query.isEmpty ? "Type to search files…" : "No files matching '\(query)'")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
                .padding(Theme.Spacing.md)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results, id: \.self) { filePath in
                            FileResultRow(filePath: filePath) {
                                onSelect(filePath)
                            }
                            if filePath != results.last {
                                Divider()
                                    .overlay(Theme.Colors.hairline)
                                    .padding(.leading, Theme.Spacing.md)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.Colors.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
                .shadow(color: Theme.Colors.shadow, radius: 12, x: 0, y: -4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onChange(of: query) { _, newQuery in
            debounceSearch(query: newQuery)
        }
        .task {
            await searchFiles(query: query)
        }
    }

    // MARK: - Search Logic

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            // Small debounce to avoid flooding the API on every keystroke
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await searchFiles(query: query)
        }
    }

    private func searchFiles(query: String) async {
        isLoading = true
        loadError = nil
        do {
            let api = FileAPI(client: apiClient)
            results = try await api.findFiles(query: query, directory: directory, limit: 20)
        } catch {
            if !Task.isCancelled {
                loadError = error.localizedDescription
            }
        }
        isLoading = false
    }
}

// MARK: - FileResultRow

private struct FileResultRow: View {
    let filePath: String
    let onTap: () -> Void

    @State private var isHovered = false

    /// Extract just the filename from the path.
    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    /// The directory portion of the path (everything before the filename).
    private var directoryPath: String {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent().relativePath
        if dir == "." { return "" }
        return dir + "/"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.sm) {
                // File type icon
                Image(systemName: FileIconStyle.symbol(for: fileName))
                    .font(.body)
                    .foregroundStyle(FileIconStyle.color(for: fileName))
                    .frame(width: 24)

                // Path with filename highlighted
                Group {
                    if directoryPath.isEmpty {
                        Text(fileName)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Theme.Colors.cloud)
                    } else {
                        Text(directoryPath)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(Theme.Colors.silver)
                        + Text(fileName)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Theme.Colors.cloud)
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 10)
            .background(isHovered ? Theme.Colors.slate : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
