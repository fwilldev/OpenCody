//
//  ProjectCardView.swift
//  OpenCody - An OpenCode Client
//
//  Created by Fabian Will on 26.02.26.
//

import SwiftUI

// MARK: - ProjectCardView

/// A glass-morphism card displaying a project summary with session count and activity.
struct ProjectCardView: View {
    let projectName: String
    let activeSessions: Int
    let lastUpdated: Double

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Top row: folder icon + name
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.cyberBlue.opacity(0.8))
                Text(projectName)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.cloud)
                    .lineLimit(1)
            }

            // Bottom row: relative time, active indicator
            HStack {
                Text(relativeTime)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.smoke)

                Spacer()

                if activeSessions > 0 {
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(Theme.Colors.neonGreen)
                            .frame(width: 6, height: 6)
                            .shadow(color: Theme.Colors.neonGreen.opacity(0.6), radius: 3)
                        Text("\(activeSessions) active")
                            .font(Theme.Fonts.codeCaption)
                            .foregroundStyle(Theme.Colors.neonGreen)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .glassCard()
    }

    // MARK: - Computed

    /// Format the most recent session update time as a relative string.
    private var relativeTime: String {
        guard lastUpdated > 0 else { return "" }
        let raw = lastUpdated
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
