import SwiftUI

struct CompactionPartView: View {
    let part: CompactionPart

    var body: some View {
        SmallBadgeView(
            icon: "arrow.triangle.2.circlepath",
            label: "Context compacted",
            color: Theme.Colors.cyberBlue
        )
    }
}
