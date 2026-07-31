import SwiftUI

struct FilePartView: View {
    let part: FilePart

    private var displayName: String {
        if let filename = part.filename, !filename.isEmpty {
            return filename
        }
        return URL(string: part.url ?? "")?.lastPathComponent ?? (part.url ?? "")
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: fileIcon(for: part.mime))
                .font(.caption)
                .foregroundStyle(Theme.Colors.cyberBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.Colors.cloud)
                    .lineLimit(1)
                Text(part.mime)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.silver)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Colors.graphite)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.Colors.hairline, lineWidth: 1)
                )
        )
    }

    private func fileIcon(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("text/") { return "doc.text" }
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.contains("zip") || mime.contains("archive") { return "archivebox" }
        return "doc"
    }
}
