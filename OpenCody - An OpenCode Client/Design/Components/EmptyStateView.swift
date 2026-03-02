import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(Theme.Colors.silver)
                .padding(.bottom, Theme.Spacing.sm)
            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Fonts.title2)
                    .foregroundStyle(Theme.Colors.cloud)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.silver)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            if let action, let label = actionLabel {
                Button(label, action: action)
                    .primaryButton()
                    .padding(.top, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
    }
}
