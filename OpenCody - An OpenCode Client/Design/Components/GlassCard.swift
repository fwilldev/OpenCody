import SwiftUI

struct GlassCard<Content: View>: View {
    var radius: CGFloat
    let content: () -> Content

    init(radius: CGFloat = Theme.Radius.card, @ViewBuilder content: @escaping () -> Content) {
        self.radius = radius
        self.content = content
    }

    var body: some View {
        content()
            .padding(Theme.Spacing.md)
            .glassCard(radius: radius)
    }
}
