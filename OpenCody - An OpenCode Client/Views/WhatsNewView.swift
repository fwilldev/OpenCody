import SwiftUI

// MARK: - WhatsNew

/// Release notes shown once per release, the first time the updated app launches.
enum WhatsNew {
    /// The release these notes describe. Bump it (and the notes) to show the sheet again.
    static let version = "1.10"

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
                        item("Notifications for OpenCode 2: get an alert when a run finishes, fails or needs your answer, even while OpenCody is closed. Allow or deny permissions right from the notification.")
                        item("To set it up, install the OpenCody plugin on your server. Settings → Notifications → your server shows how.")
                        item("Notifications now arrive by push only, so they need OpenCode 2 with the plugin. OpenCode 1.x servers no longer send them.")
                        item("Windows servers: folder paths like C:\\Projects\\App no longer get a leading slash. Sessions created before this update keep the broken path, so start a new session in those projects.")
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
