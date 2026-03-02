import SwiftUI

struct PrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.cyberBlue.opacity(0.25))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button).stroke(Theme.Colors.cyberBlue.opacity(0.5), lineWidth: 1))
            .shadow(color: Theme.Colors.cyberBlue.opacity(0.2), radius: 8, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Colors.silver)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button).stroke(Color.white.opacity(Theme.Glass.borderOpacity), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct DestructiveGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.hotPink.opacity(0.25))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button).stroke(Theme.Colors.hotPink.opacity(0.5), lineWidth: 1))
            .shadow(color: Theme.Colors.hotPink.opacity(0.2), radius: 8, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func primaryButton() -> some View { buttonStyle(PrimaryGlassButtonStyle()) }
    func secondaryButton() -> some View { buttonStyle(SecondaryGlassButtonStyle()) }
    func destructiveButton() -> some View { buttonStyle(DestructiveGlassButtonStyle()) }
}
