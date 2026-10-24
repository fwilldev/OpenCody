import SwiftUI

// MARK: - WhatsNew

/// Release notes shown once per release, the first time the updated app launches.
enum WhatsNew {
    /// The release these notes describe. Bump it (and the notes) to show the sheet again.
    static let version = "1.9"

    private static let seenKey = "whatsNew_lastSeenVersion"

    /// Whether the notes for `version` still need to be shown.
    static func isPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: seenKey) != version
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: seenKey)
    }
}

// MARK: - WhatsNewView

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Scrolls so large Dynamic Type sizes never clip the notes.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("What's New in OpenCody \(WhatsNew.version)")
                        .font(Theme.Fonts.title2)
                        .foregroundStyle(Theme.Colors.cloud)
                        .padding(.top, Theme.Spacing.xl)

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        item("Made for iPhone Duo: the outer display keeps the familiar iPhone layout, unfold it and your projects and chat sit side by side.")
                        item("Folding, unfolding and resizing keep your place: the open chat, its scroll position and the message you were typing.")
                        item("On iPad, resizing the window in Split View no longer jumps back to the project list.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .primaryButton()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.deepBlack)
        .presentationDetents([.medium, .large])
    }

    private func item(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text("•")
                .foregroundStyle(Theme.Colors.cyberBlue)
            Text(text)
                .foregroundStyle(Theme.Colors.cloud)
        }
        .font(Theme.Fonts.body)
    }
}

#Preview {
    Text("App")
        .sheet(isPresented: .constant(true)) { WhatsNewView() }
}
