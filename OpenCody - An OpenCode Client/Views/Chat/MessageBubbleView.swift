import SwiftUI

struct MessageBubbleView: View {
    let messageWithParts: MessageWithParts
    let viewModel: ChatViewModel

    private var roleIcon: String {
        switch messageWithParts.message.role {
        case .user: return "person"
        case .assistant: return "cpu"
        }
    }

    private var isLocalPending: Bool {
        messageWithParts.id.hasPrefix("local-user-")
    }

    private var roleLabel: String {
        switch messageWithParts.message.role {
        case .user: return "you"
        case .assistant: return "opencode"
        }
    }

    private var isUser: Bool {
        messageWithParts.message.role == .user
    }

    private var roleColor: Color {
        switch messageWithParts.message.role {
        case .user: return Theme.Colors.cyberBlue
        case .assistant: return Theme.Colors.neonGreen
        }
    }

    private var createdAt: Double {
        switch messageWithParts.message {
        case .user(let m): return m.time.created
        case .assistant(let m): return m.time.created
        }
    }

    /// Indicates if there is any copyable text content.
    private var hasCopyableText: Bool {
        messageWithParts.parts.contains { part in
            switch part {
            case .text(let p): return !p.text.isEmpty
            case .reasoning(let p): return !p.text.isEmpty
            default: return false
            }
        }
    }

    /// Build copyable text content on demand (avoid heavy work in body).
    private func buildCopyableText() -> String {
        messageWithParts.parts.compactMap { part in
            switch part {
            case .text(let p): return p.text
            case .reasoning(let p): return p.text
            default: return nil
            }
        }.joined(separator: "\n\n")
    }


    private var timestamp: String {
        // Guard against millisecond timestamps (values > year 3000 in seconds)
        let raw = createdAt
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        // Fresh messages would render as "in 0 sec" due to clock skew — show "now".
        if abs(date.timeIntervalSinceNow) < 60 { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // User messages sit on the trailing edge like a classic chat;
            // assistant messages keep the full width for code and tool output.
            if isUser {
                Spacer(minLength: Theme.Spacing.xxl)
            }

            bubbleCard

            if !isUser {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var bubbleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: roleIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(roleColor)
                }
                Text(roleLabel)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(roleColor)
                Spacer()
                if isLocalPending {
                    Text("Sending…")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.Colors.smoke)
                } else {
                    Text(timestamp)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.Colors.smoke)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 6)

            // Parts
            if messageWithParts.parts.isEmpty {
                Text("…")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.smoke)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.sm)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messageWithParts.parts) { part in
                        PartRendererView(part: part, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isUser ? Theme.Colors.cyberBlue.opacity(0.09) : Theme.Colors.carbon)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isUser ? Theme.Colors.cyberBlue.opacity(0.22) : Theme.Colors.hairline,
                            lineWidth: 1
                        )
                )
        )
        .opacity(isLocalPending ? 0.7 : 1.0)
        .contextMenu {
            if hasCopyableText {
                Button {
                    UIPasteboard.general.string = buildCopyableText()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}
