import SwiftUI

enum AppError: Error, Sendable {
    case network(String)
    case auth(Int)
    case server(Int, String)
    case validation(Int, String)
    case sse(String)

    var title: String {
        switch self {
        case .network: return "Connection Error"
        case .auth: return "Authentication Failed"
        case .server(let code, _): return "Server Error (\(code))"
        case .validation(let code, _): return "Request Error (\(code))"
        case .sse: return "Stream Error"
        }
    }

    var message: String {
        switch self {
        case .network(let msg): return msg
        case .auth(let code): return code == 401 ? "Invalid credentials." : "Access denied."
        case .server(_, let msg): return msg
        case .validation(_, let msg): return msg
        case .sse(let msg): return msg
        }
    }

    var accentColor: Color {
        switch self {
        case .network, .server: return Theme.Colors.neonOrange
        case .auth, .sse: return Theme.Colors.hotPink
        case .validation: return Theme.Colors.electricPurple
        }
    }

    var icon: String {
        switch self {
        case .network: return "wifi.exclamationmark"
        case .auth: return "lock.slash"
        case .server: return "server.rack"
        case .validation: return "exclamationmark.triangle"
        case .sse: return "bolt.slash"
        }
    }
}

struct ErrorBanner: View {
    let error: AppError
    let onDismiss: () -> Void
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: error.icon)
                .font(.body.weight(.medium))
                .foregroundStyle(error.accentColor)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.Colors.cloud)
                Text(error.message).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.silver).lineLimit(3)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Dismiss", systemImage: "xmark") {
                withAnimation(.easeOut(duration: 0.2)) { isVisible = false } completion: { onDismiss() }
            }
            .labelStyle(.iconOnly)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.Colors.silver)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .padding(.leading, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.trailing, Theme.Spacing.xs)
        .background(.ultraThinMaterial)
        .background(Theme.Colors.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(error.accentColor).frame(width: 4) }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).stroke(error.accentColor.opacity(0.3), lineWidth: 1))
        .offset(y: isVisible || reduceMotion ? 0 : -80)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isVisible = true }
            AccessibilityNotification.Announcement("\(error.title). \(error.message)").post()
        }
    }
}
