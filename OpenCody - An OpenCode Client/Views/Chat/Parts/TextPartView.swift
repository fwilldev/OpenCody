import SwiftUI
import MarkdownUI

struct TextPartView: View {
    let part: TextPart

    private static let markdownTheme: MarkdownUI.Theme = MarkdownUI.Theme()
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            ForegroundColor(Theme.Colors.neonGreen)
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(13)
                    ForegroundColor(Theme.Colors.neonGreen)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.graphite)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        }

    var body: some View {
        if part.text.isEmpty {
            EmptyView()
        } else {
            Markdown(part.text)
                .markdownTheme(Self.markdownTheme)
                .markdownTextStyle {
                    ForegroundColor(Theme.Colors.cloud)
                    FontSize(15)
                }
                #if DEBUG
                .onAppear {
                    print("[TextPartView] rendering text (\(part.text.count) chars): \(part.text.prefix(200))")
                }
                #endif
        }
    }
}