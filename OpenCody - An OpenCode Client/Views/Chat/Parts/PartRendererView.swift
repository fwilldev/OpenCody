import SwiftUI

/// Dispatches each Part variant to the correct sub-view.
struct PartRendererView: View {
    let part: Part
    let viewModel: ChatViewModel

    var body: some View {
        switch part {
        case .text(let p):
            TextPartView(part: p)
        case .tool(let p):
            ToolPartView(part: p, viewModel: viewModel)
        case .reasoning(let p):
            ReasoningPartView(part: p)
        case .agent(let p):
            AgentPartView(part: p)
        case .stepStart(let p):
            StepStartView(part: p)
        case .stepFinish(let p):
            StepFinishView(part: p)
        case .retry(let p):
            RetryPartView(part: p)
        case .compaction(let p):
            CompactionPartView(part: p)
        case .subtask(let p):
            SubtaskPartView(part: p)
        case .file(let p):
            FilePartView(part: p)
        case .snapshot:
            SmallBadgeView(icon: "camera", label: "Snapshot captured", color: Theme.Colors.silver)
        case .patch(let p):
            SmallBadgeView(
                icon: "doc.badge.arrow.up",
                label: (p.files ?? []).isEmpty ? "Patch applied" : "Files patched: \((p.files ?? []).joined(separator: ", "))",
                color: Theme.Colors.neonOrange
            )
        case .unknown:
            // Unknown/future part type — render nothing
            EmptyView()
        }
    }
}
