//
//  SessionCardView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 25.02.26.
//

import SwiftUI

// MARK: - SessionCardView

/// A glass-morphism card displaying session summary information.
struct SessionCardView: View {
    let session: Session
    let status: SessionStatus?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Top row: title + status badge
            HStack {
                Text(session.title.isEmpty ? "Untitled Session" : session.title)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.cloud)
                    .lineLimit(1)

                Spacer()

                if isSessionRunning {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Colors.cyberBlue)
                }

                StatusBadge(
                    status: connectionStatusFromSession,
                    showLabel: true
                )
            }

            // Middle: directory path
            Text(session.directory)
                .font(Theme.Fonts.codeCaption)
                .foregroundStyle(Theme.Colors.silver)
                .lineLimit(1)
                .truncationMode(.middle)

            // Bottom row: summary + relative time
            HStack {
                // Summary info
                if let summary = session.summary {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.smoke)
                        Text("\(summary.files) file\(summary.files == 1 ? "" : "s")")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.smoke)

                        Text("·")
                            .foregroundStyle(Theme.Colors.smoke)

                        Text("+\(summary.additions)")
                            .font(Theme.Fonts.codeCaption)
                            .foregroundStyle(Theme.Colors.neonGreen.opacity(0.8))
                        Text("-\(summary.deletions)")
                            .font(Theme.Fonts.codeCaption)
                            .foregroundStyle(Theme.Colors.hotPink.opacity(0.8))
                    }
                } else {
                    Text("No changes yet")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.smoke)
                }

                Spacer()

                // Relative time
                Text(relativeTime)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.smoke)
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    // MARK: - Computed

    /// Convert SessionStatus to ConnectionStatus for the badge.
    private var connectionStatusFromSession: ConnectionStatus {
        guard let status else { return .idle }
        switch status {
        case .idle:
            return .idle
        case .busy:
            return .active
        case .retry:
            return .connecting
        }
    }

    private var isSessionRunning: Bool {
        guard let status else { return false }
        switch status {
        case .idle:
            return false
        case .busy, .retry:
            return true
        }
    }


    /// Format the session's last update time as a relative string.
    private var relativeTime: String {
        // Guard against millisecond timestamps (values > year 3000 in seconds)
        let raw = session.time.updated
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
