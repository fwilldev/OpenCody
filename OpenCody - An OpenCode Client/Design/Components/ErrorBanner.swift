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

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: error.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(error.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(Theme.Fonts.body.weight(.semibold)).foregroundStyle(Theme.Colors.cloud)
                Text(error.message).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.silver).lineLimit(2)
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Colors.silver).padding(Theme.Spacing.xs)
            }
        }
        .padding(.leading, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.trailing, Theme.Spacing.sm)
        .background(.ultraThinMaterial)
        .background(Theme.Colors.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(error.accentColor).frame(width: 4) }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).stroke(error.accentColor.opacity(0.3), lineWidth: 1))
        .offset(y: isVisible ? 0 : -80)
        .opacity(isVisible ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isVisible = true } }
    }
}
