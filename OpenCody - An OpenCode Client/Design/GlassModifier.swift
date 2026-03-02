import SwiftUI

struct GlassModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Theme.Colors.carbon)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Theme.Colors.graphite, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(GlassModifier(radius: radius))
    }
    func glassButton() -> some View {
        modifier(GlassModifier(radius: Theme.Radius.button))
    }
    func glassSheet() -> some View {
        modifier(GlassModifier(radius: Theme.Radius.sheet))
    }
}
