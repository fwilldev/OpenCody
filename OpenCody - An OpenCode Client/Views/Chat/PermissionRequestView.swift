//
//  PermissionRequestView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Full modal sheet displayed when a tool requires user permission.
/// Replaces the inline overlay in ChatView — to be shown as a `.sheet(item:)`.
struct PermissionRequestView: View {
    let permission: Permission
    /// Called with the chosen decision — `.once`, `.always`, or `.reject`.
    let onDecision: (PermissionReplyDecision) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Header icon + title
                    HStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.Colors.neonOrange.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "lock.shield")
                                .font(.title2)
                                .foregroundStyle(Theme.Colors.neonOrange)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Permission Required")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.Colors.cloud)
                            Text("A tool is requesting access")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.silver)
                        }
                    }
                    .padding(.top, Theme.Spacing.md)

                    // Tool details card
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Label("Permission", systemImage: "wrench.and.screwdriver")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.silver)

                        Text(permission.displayTitle)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Theme.Colors.cyberBlue)

                        if !permission.patterns.isEmpty {
                            Divider().overlay(Theme.Colors.border)
                            Label(
                                permission.patterns.count == 1 ? "Target" : "Targets",
                                systemImage: "text.magnifyingglass"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.silver)

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(permission.patterns, id: \.self) { pat in
                                    Text(permission.patterns.count == 1 ? pat : "• " + pat)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.cloud)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                            .background(Theme.Colors.graphite)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.glassFill))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1))
                    )

                    // Warning note
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.neonOrange)
                        Text("Only allow tools you trust. Denied requests pause the current operation.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.silver)
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: Theme.Spacing.sm) {
                        Button {
                            onDecision(.once)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Allow Once")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(Theme.Colors.cyberBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.Colors.cyberBlue.opacity(0.15))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.cyberBlue.opacity(0.4), lineWidth: 1))
                            )
                        }

                        if permission.supportsAlways {
                            Button {
                                onDecision(.always)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.badge.checkmark")
                                    Text("Always Allow")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(Theme.Colors.cloud)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.Colors.fillMuted)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.borderStrong, lineWidth: 1))
                                )
                            }
                        }

                        Button {
                            onDecision(.reject)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Deny")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(Theme.Colors.hotPink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.Colors.hotPink.opacity(0.1))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Colors.hotPink.opacity(0.3), lineWidth: 1))
                            )
                        }
                    }
                    .padding(.bottom, Theme.Spacing.md)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDecision(.reject)
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.silver)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
