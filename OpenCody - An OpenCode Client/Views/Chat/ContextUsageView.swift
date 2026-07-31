//
//  ContextUsageView.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// Sheet displaying context/token usage metrics for the current session.
/// Shows total tokens, context usage percentage, cost breakdown, and per-category token counts.
struct ContextUsageView: View {
    let session: Session
    let viewModel: ChatViewModel
    let apiClient: APIClient

    @Environment(\.dismiss) private var dismiss
    @State private var providers: [Provider] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.deepBlack.ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading…")
                        .tint(Theme.Colors.cyberBlue)
                        .foregroundStyle(Theme.Colors.silver)
                } else {
                    let metrics = buildMetrics()
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            headerCard(metrics: metrics)
                            statsGrid(metrics: metrics)
                        }
                        .padding(Theme.Spacing.lg)
                    }
                }
            }
            .navigationTitle("Context Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.Colors.silver)
                }
            }
        }
        .presentationBackground(Theme.Colors.carbon)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadProviders()
        }
    }

    // MARK: - Header Card

    @ViewBuilder
    private func headerCard(metrics: ContextMetrics) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // Usage circle + headline
            HStack(spacing: Theme.Spacing.md) {
                usageCircle(usage: metrics.context?.usage, total: metrics.context?.total ?? 0)

                VStack(alignment: .leading, spacing: 4) {
                    if let ctx = metrics.context {
                        Text(formatNumber(ctx.total) + " tokens")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.cloud)
                        if let usage = ctx.usage {
                            Text("\(usage)% of context used")
                                .font(.caption)
                                .foregroundStyle(usageColor(usage))
                        }
                        if let limit = ctx.limit {
                            Text("Limit: " + formatNumber(limit))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.silver)
                        }
                    } else {
                        Text("No token data")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.silver)
                        Text("Send a message to see usage")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.smoke)
                    }
                }
                Spacer()
            }

            // Cost
            HStack {
                Text("Total Cost")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.silver)
                Spacer()
                Text(formatCost(metrics.totalCost))
                    .font(Theme.Fonts.code)
                    .foregroundStyle(Theme.Colors.neonGreen)
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .fill(Theme.Colors.neonGreen.opacity(0.08))
            )
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Colors.glassFill))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).stroke(Theme.Colors.border, lineWidth: Theme.Glass.borderWidth))
        )
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(metrics: ContextMetrics) -> some View {
        let messageCounts = countMessages()

        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Theme.Spacing.sm),
            GridItem(.flexible(), spacing: Theme.Spacing.sm)
        ], spacing: Theme.Spacing.md) {
            // Provider & Model
            if let ctx = metrics.context {
                statCell(label: "Provider", value: ctx.providerLabel)
                statCell(label: "Model", value: ctx.modelLabel)
            }

            // Token breakdown
            if let ctx = metrics.context {
                statCell(label: "Input Tokens", value: formatNumber(ctx.input))
                statCell(label: "Output Tokens", value: formatNumber(ctx.output))

                if ctx.reasoning > 0 {
                    statCell(label: "Reasoning", value: formatNumber(ctx.reasoning))
                }

                statCell(label: "Cache Read", value: formatNumber(ctx.cacheRead))
                statCell(label: "Cache Write", value: formatNumber(ctx.cacheWrite))
            }

            // Message counts
            statCell(label: "Messages", value: "\(messageCounts.total)")
            statCell(label: "User", value: "\(messageCounts.user)")
            statCell(label: "Assistant", value: "\(messageCounts.assistant)")

            // Session timestamps
            statCell(label: "Created", value: formatTimestamp(session.time.created))
            if let ctx = metrics.context {
                statCell(label: "Last Activity", value: formatTimestamp(ctx.message.time.created))
            }
        }
    }

    @ViewBuilder
    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.silver)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Colors.cloud)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .fill(Theme.Colors.graphite)
        )
    }

    // MARK: - Usage Circle

    @ViewBuilder
    private func usageCircle(usage: Int?, total: Int) -> some View {
        let fraction = usage.map { Double($0) / 100.0 } ?? 0.0
        let color = usageColor(usage ?? 0)

        ZStack {
            Circle()
                .stroke(Theme.Colors.slate, lineWidth: 4)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))
            if let usage {
                Text("\(usage)%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            } else {
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.smoke)
            }
        }
    }

    // MARK: - Metrics Computation

    private struct ContextDetail {
        let message: AssistantMessage
        let providerLabel: String
        let modelLabel: String
        let limit: Int?
        let input: Int
        let output: Int
        let reasoning: Int
        let cacheRead: Int
        let cacheWrite: Int
        let total: Int
        let usage: Int?
    }

    private struct ContextMetrics {
        let totalCost: Double
        let context: ContextDetail?
    }

    private func buildMetrics() -> ContextMetrics {
        // Sum cost across all assistant messages
        let totalCost = viewModel.messages.reduce(0.0) { sum, mwp in
            if case .assistant(let am) = mwp.message {
                return sum + (am.cost ?? 0)
            }
            return sum
        }

        // Find last assistant message with non-zero tokens
        let lastWithTokens: AssistantMessage? = {
            for mwp in viewModel.messages.reversed() {
                if case .assistant(let am) = mwp.message, let tokens = am.tokens {
                    let total = tokens.input + tokens.output + tokens.reasoning
                        + (tokens.cache?.read ?? 0) + (tokens.cache?.write ?? 0)
                    if total > 0 { return am }
                }
            }
            return nil
        }()

        guard let am = lastWithTokens, let tokens = am.tokens else {
            return ContextMetrics(totalCost: totalCost, context: nil)
        }

        let input = tokens.input
        let output = tokens.output
        let reasoning = tokens.reasoning
        let cacheRead = tokens.cache?.read ?? 0
        let cacheWrite = tokens.cache?.write ?? 0
        let total = input + output + reasoning + cacheRead + cacheWrite

        // Look up provider/model for labels and context limit
        let provider = providers.first { $0.id == am.providerID }
        let model = am.modelID.flatMap { provider?.models[$0] }
        let limit = model?.limit.context

        let providerLabel = provider?.name ?? am.providerID ?? "Unknown"
        let modelLabel = model?.name ?? am.modelID ?? "Unknown"

        let usage: Int? = limit.map { Int(round(Double(total) / Double($0) * 100)) }

        return ContextMetrics(
            totalCost: totalCost,
            context: ContextDetail(
                message: am,
                providerLabel: providerLabel,
                modelLabel: modelLabel,
                limit: limit,
                input: input,
                output: output,
                reasoning: reasoning,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                total: total,
                usage: usage
            )
        )
    }

    private func countMessages() -> (total: Int, user: Int, assistant: Int) {
        var user = 0
        var assistant = 0
        for mwp in viewModel.messages {
            switch mwp.message {
            case .user: user += 1
            case .assistant: assistant += 1
            }
        }
        return (user + assistant, user, assistant)
    }

    // MARK: - Formatting

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatNumber(_ n: Int?) -> String {
        guard let n else { return "—" }
        return formatNumber(n)
    }

    private func formatCost(_ cost: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: cost)) ?? "$\(cost)"
    }

    private func formatTimestamp(_ ts: Double) -> String {
        guard ts > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: ts)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func usageColor(_ usage: Int) -> Color {
        if usage >= 90 { return Theme.Colors.hotPink }
        if usage >= 70 { return Theme.Colors.neonOrange }
        return Theme.Colors.cyberBlue
    }

    // MARK: - Data Loading

    private func loadProviders() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = ProviderAPI(client: apiClient)
            let response = try await api.list()
            providers = response.all
        } catch {
            // Non-fatal — metrics just won't show provider/model labels or context limit
            providers = []
        }
    }
}
