import SwiftUI

struct SubtaskPartView: View {
    let part: SubtaskPart

    var body: some View {
        SmallBadgeView(
            icon: "square.stack",
            label: (part.description ?? "").isEmpty ? "Subtask" : part.description!,
            color: Theme.Colors.electricPurple
        )
    }
}
