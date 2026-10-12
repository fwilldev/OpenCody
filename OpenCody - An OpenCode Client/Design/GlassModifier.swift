import SwiftUI

struct GlassModifier: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Theme.Colors.carbon, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Theme.Colors.graphite, lineWidth: 1)
            }
    }
}

extension View {
    func glassCard(radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(GlassModifier(radius: radius))
    }
}
