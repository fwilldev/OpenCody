import SwiftUI

// MARK: - RefreshButton

/// A toolbar-friendly refresh button with three visual states:
/// - idle: shows `arrow.clockwise`
/// - refreshing: shows a spinning `ProgressView`
/// - done: briefly shows a `checkmark` then returns to idle
struct RefreshButton: View {
    let action: () async -> Void

    @State private var state: RefreshState = .idle

    private enum RefreshState {
        case idle, refreshing, done
    }

    var body: some View {
        Button {
            guard state == .idle else { return }
            Task {
                state = .refreshing
                await action()
                state = .done
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(.easeInOut(duration: 0.25)) {
                    state = .idle
                }
            }
        } label: {
            Group {
                switch state {
                case .idle:
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Theme.Colors.cyberBlue)
                case .refreshing:
                    ProgressView()
                        .tint(Theme.Colors.cyberBlue)
                        .scaleEffect(0.8)
                case .done:
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Colors.neonGreen)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state == .refreshing)
        }
        .disabled(state != .idle)
    }
}
