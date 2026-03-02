import SwiftUI

enum ConnectionStatus: Sendable {
    case active, idle, error, connecting

    var color: Color {
        switch self {
        case .active: return Theme.Colors.neonGreen
        case .idle: return Theme.Colors.silver
        case .error: return Theme.Colors.hotPink
        case .connecting: return Theme.Colors.neonOrange
        }
    }

    var label: String {
        switch self {
        case .active: return "Done"
        case .idle: return "Idle"
        case .error: return "Error"
        case .connecting: return "Running"
        }
    }

    var isAnimating: Bool { self == .connecting }
}

struct StatusBadge: View {
    let status: ConnectionStatus
    var showLabel: Bool = true
    @State private var pulse = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
                .shadow(color: status.color.opacity(0.8), radius: pulse && status.isAnimating ? 4 : 2)
                .scaleEffect(pulse && status.isAnimating ? 1.3 : 1.0)
                .animation(
                    status.isAnimating ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                    value: pulse
                )
                .onAppear { pulse = true }
            if showLabel {
                Text(status.label)
                    .font(Theme.Fonts.codeCaption)
                    .foregroundStyle(status.color)
            }
        }
    }
}
