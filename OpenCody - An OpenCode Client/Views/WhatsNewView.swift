import SwiftUI

// MARK: - WhatsNew

/// Release notes shown once per release, the first time the updated app launches.
enum WhatsNew {
    /// The release these notes describe. Bump it (and the notes) to show the sheet again.
    static let version = "1.7"

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
            Text("OpenCody \(WhatsNew.version) Changelog")
                .font(Theme.Fonts.title2)
                .foregroundStyle(Theme.Colors.cloud)
                .padding(.top, Theme.Spacing.xl)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                item("OpenCody now supports OpenCode 2.x.")
                item("Some improvements and bug fixes.")
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    item("OpenCody is now open source.")
                    Link("github.com/fwilldev/OpenCody", destination: AppLinks.sourceCode)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.cyberBlue)
                        .padding(.leading, Theme.Spacing.lg)
                }
            }

            Spacer()

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
