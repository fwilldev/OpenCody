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
            switch state {
            case .idle:
                Label("Refresh", systemImage: "arrow.clockwise")
            case .refreshing:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing")
            case .done:
                Label("Refreshed", systemImage: "checkmark")
                    .foregroundStyle(Theme.Colors.neonGreen)
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .sensoryFeedback(.success, trigger: state == .done) { _, done in done }
        .disabled(state != .idle)
    }
}
