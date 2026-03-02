import SwiftUI

struct RetryPartView: View {
    let part: RetryPart

    var body: some View {
        SmallBadgeView(
            icon: "exclamationmark.triangle",
            label: "Retrying… (attempt \(part.attempt))",
            color: Theme.Colors.neonOrange
        )
    }
}
