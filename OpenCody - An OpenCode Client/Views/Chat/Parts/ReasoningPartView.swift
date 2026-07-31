import SwiftUI

struct ReasoningPartView: View {
    let part: ReasoningPart
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.electricPurple)
                    Text("Reasoning")
                        .font(.caption.bold().italic())
                        .foregroundStyle(Theme.Colors.silver)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.silver)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(Theme.Colors.hairline)

                Text(part.text)
                    .font(.subheadline.italic())
                    .foregroundStyle(Theme.Colors.silver)
                    .padding(Theme.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Colors.electricPurple.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.Colors.electricPurple.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
