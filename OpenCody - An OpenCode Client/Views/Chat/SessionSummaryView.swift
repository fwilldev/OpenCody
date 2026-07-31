//
//  SessionSummaryView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Sheet displaying the summary text for a session.
/// Triggered by the Summarize action in SessionActionsMenu or a session.summary SSE event.
struct SessionSummaryView: View {
    let sessionTitle: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        // Header card
                        HStack(spacing: Theme.Spacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.Colors.electricPurple.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "sparkles.rectangle.stack")
                                    .font(.title3)
                                    .foregroundStyle(Theme.Colors.electricPurple)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Compaction Triggered")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.cloud)
                                Text(sessionTitle.isEmpty ? "Untitled Session" : sessionTitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.silver)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }

                        // Info text
                        Text("Context compaction has been triggered. The session context will be summarized in the background to free up token space.")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.cloud)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.glassFill))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1))
                            )
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
