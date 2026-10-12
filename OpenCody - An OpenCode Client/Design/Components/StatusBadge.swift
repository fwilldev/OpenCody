import SwiftUI

enum ConnectionStatus: Sendable {
    case active, idle, error, connecting, offline

    var color: Color {
        switch self {
        case .active: return Theme.Colors.neonGreen
        case .idle: return Theme.Colors.silver
        case .error: return Theme.Colors.hotPink
        case .connecting: return Theme.Colors.neonOrange
        case .offline: return Theme.Colors.hotPink
        }
    }

    var label: String {
        switch self {
        case .active: return "Done"
        case .idle: return "Idle"
        case .error: return "Error"
        case .connecting: return "Running"
        case .offline: return "Offline"
        }
    }

    var isAnimating: Bool { self == .connecting }
}

struct StatusBadge: View {
    let status: ConnectionStatus
    var showLabel: Bool = true
    /// Wording for this context (e.g. "Connected"); defaults to the status label.
    var label: String? = nil
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { status.isAnimating && !reduceMotion }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
                .shadow(color: status.color.opacity(0.8), radius: pulse && animates ? 4 : 2)
                .scaleEffect(pulse && animates ? 1.3 : 1.0)
                .animation(
                    animates ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                    value: pulse
                )
                .onAppear { pulse = true }
            if showLabel {
                Text(label ?? status.label)
                    .font(Theme.Fonts.codeCaption)
                    .foregroundStyle(status.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? status.label)
    }
}
