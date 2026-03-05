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
        case .user: return "You"
        case .assistant: return "Assistant"
        }
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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: Date(timeIntervalSince1970: seconds), relativeTo: Date())
    }

    var body: some View {
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
                    .font(.caption.bold())
                    .foregroundStyle(roleColor)
                Spacer()
                if isLocalPending {
                    Text("Sending…")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.smoke)
                } else {
                    Text(timestamp)
                        .font(.caption2)
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Colors.carbon)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
