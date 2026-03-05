import SwiftUI
import MarkdownUI

struct TextPartView: View {
    let part: TextPart
    @State private var showFullText = false

    private let previewLimit = 8000
    private var isTruncated: Bool {
        part.text.count > previewLimit
    }
    private var displayText: String {
        if showFullText || !isTruncated {
            return part.text
        }
        return String(part.text.prefix(previewLimit)) + "…"
    }

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
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if showFullText || !isTruncated {
                    Markdown(displayText)
                        .markdownTheme(Self.markdownTheme)
                        .markdownTextStyle {
                            ForegroundColor(Theme.Colors.cloud)
                            FontSize(15)
                        }
                } else {
                    Text(displayText)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.cloud)
                }

                if isTruncated && !showFullText {
                    Button("Show full response") {
                        showFullText = true
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.cyberBlue)
                }
            }
                #if DEBUG
                .onAppear {
                    print("[TextPartView] rendering text (\(part.text.count) chars): \(part.text.prefix(200))")
                }
                #endif
        }
    }
}
