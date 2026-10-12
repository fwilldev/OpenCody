import SwiftUI

/// The app's button roles, on the system Liquid Glass styles (which also dim when disabled).
extension View {
    func primaryButton() -> some View { buttonStyle(.glassProminent).tint(Theme.Colors.cyberBlue) }
    func secondaryButton() -> some View { buttonStyle(.glass) }
    func destructiveButton() -> some View { buttonStyle(.glassProminent).tint(Theme.Colors.hotPink) }
}
