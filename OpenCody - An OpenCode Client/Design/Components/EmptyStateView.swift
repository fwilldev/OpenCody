import SwiftUI

/// Empty, offline and error states: the system `ContentUnavailableView` with an
/// optional action button.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.Colors.cloud)
        } description: {
            Text(message)
                .foregroundStyle(Theme.Colors.silver)
        } actions: {
            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .primaryButton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
