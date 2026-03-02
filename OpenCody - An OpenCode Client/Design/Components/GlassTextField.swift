import SwiftUI

struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
            }
        }
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Colors.cloud)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).stroke(Color.white.opacity(Theme.Glass.borderOpacity), lineWidth: 1))
        .tint(Theme.Colors.cyberBlue)
    }
}
