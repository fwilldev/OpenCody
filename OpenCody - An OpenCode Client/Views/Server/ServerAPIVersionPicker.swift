import SwiftUI

// MARK: - ServerAPIVersionPicker

/// Lets the user choose which OpenCode server generation a server runs.
///
/// Shared by the add and edit forms. 1.x is the default; 2.x needs to be chosen
/// explicitly because the two APIs are not compatible.
struct ServerAPIVersionPicker: View {
    @Binding var selection: ServerAPIVersion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Server Version")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)

            Picker("Server Version", selection: $selection) {
                ForEach(ServerAPIVersion.allCases) { version in
                    Text(version.displayName).tag(version)
                }
            }
            .pickerStyle(.segmented)

            Text(hint)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.silver)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hint: String {
        switch selection {
        case .v1:
            return "For servers installed as opencode-ai (the default)."
        case .v2:
            return "For servers installed as @opencode/cli. The username is always \"opencode\"."
        }
    }
}
