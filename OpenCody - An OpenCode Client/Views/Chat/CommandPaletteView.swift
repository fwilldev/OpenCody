//
//  CommandPaletteView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Floating overlay shown above the chat input when the user types "/" .
/// Loads slash commands from CommandAPI, filters in real-time, and calls back
/// with the selected command's full name (including the leading "/").
struct CommandPaletteView: View {
    let apiClient: APIClient
    /// The query after the "/" prefix (e.g. "" or "com" or "compact").
    let query: String
    /// Called with the full command string to insert, e.g. "/compact".
    let onSelect: (String) -> Void
    /// Called when the palette should be dismissed without a selection.
    let onDismiss: () -> Void

    @State private var commands: [SlashCommand] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil

    private var filtered: [SlashCommand] {
        if query.isEmpty { return commands }
        return commands.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.description?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.electricPurple)
                Text("Slash Commands")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.electricPurple)
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
                .overlay(Color.white.opacity(0.08))

            // Content area
            if isLoading && commands.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Theme.Colors.cyberBlue)
                    Text("Loading commands…")
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
            } else if filtered.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                    Text(query.isEmpty ? "No commands available" : "No commands matching '/\(query)'")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                }
                .padding(Theme.Spacing.md)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { command in
                            CommandRow(command: command, query: query) {
                                onSelect("/" + command.name)
                            }
                            if command.id != filtered.last?.id {
                                Divider()
                                    .overlay(Color.white.opacity(0.05))
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
                        .fill(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: -4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await loadCommands()
        }
    }

    private func loadCommands() async {
        isLoading = true
        loadError = nil
        do {
            let api = CommandAPI(client: apiClient)
            commands = try await api.list()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - CommandRow

private struct CommandRow: View {
    let command: SlashCommand
    let query: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                // Command name with matched portion highlighted
                Text("/")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.Colors.electricPurple)
                + Text(command.name)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.Colors.cloud)

                Spacer()

                if let desc = command.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.silver)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }

                if command.agent != nil {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                }
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
