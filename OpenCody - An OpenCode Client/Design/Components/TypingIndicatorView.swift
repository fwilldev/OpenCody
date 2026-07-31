import SwiftUI

/// Chat typing indicator shown while OpenCode generates a response.
/// Mirrors the assistant bubble style: avatar plus three pulsing dots.
struct TypingIndicatorView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.neonGreen.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.neonGreen)
                    .symbolEffect(.pulse, options: .repeating, isActive: isAnimating)
            }

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.Colors.neonGreen)
                        .frame(width: 6, height: 6)
                        .opacity(isAnimating ? 1 : 0.2)
                        .scaleEffect(isAnimating ? 1 : 0.7)
                        .animation(
                            .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Colors.carbon)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.Colors.hairline, lineWidth: 1)
                    )
            )
        }
        .onAppear { isAnimating = true }
    }
}
