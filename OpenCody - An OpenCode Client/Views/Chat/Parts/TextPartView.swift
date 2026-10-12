import SwiftUI
import MarkdownUI

struct TextPartView: View {
    let part: TextPart
    @State private var showFullText = false
    /// Follows Dynamic Type; MarkdownUI takes a point size, not a text style.
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 15

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
            FontSize(.em(0.87))
            ForegroundColor(Theme.Colors.neonGreen)
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.87))
                    ForegroundColor(Theme.Colors.neonGreen)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.graphite)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.Colors.hairline, lineWidth: 1)
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
                            FontSize(bodySize)
                        }
                } else {
                    Text(displayText)
                        .font(.system(size: bodySize))
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
        }
    }
}
