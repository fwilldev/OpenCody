import SwiftUI

struct AgentPartView: View {
    let part: AgentPart

    var body: some View {
        SmallBadgeView(
            icon: "arrow.right.circle",
            label: "Agent: \(part.name)",
            color: Theme.Colors.electricPurple
        )
    }
}
