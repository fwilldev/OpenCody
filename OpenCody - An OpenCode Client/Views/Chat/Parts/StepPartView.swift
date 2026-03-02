import SwiftUI

struct StepStartView: View {
    let part: StepStartPart

    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            Text("Step")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Colors.smoke)
                .padding(.horizontal, 8)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

struct StepFinishView: View {
    let part: StepFinishPart

    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            VStack(spacing: 2) {
                Text(part.reason.isEmpty ? "Step finished" : part.reason)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.smoke)
                if let cost = part.cost, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Colors.smoke.opacity(0.7))
                }
            }
            .padding(.horizontal, 8)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}
