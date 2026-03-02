import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

enum Theme {
    enum Colors {
        static let deepBlack = Color(hex: "0C0C0C")
        static let carbon = Color(hex: "141414")
        static let graphite = Color(hex: "1E1E1E")
        static let slate = Color(hex: "2D2D2D")
        static let smoke = Color(hex: "404040")
        static let silver = Color(hex: "8B8B8B")
        static let cloud = Color(hex: "E5E5E5")
        static let neonGreen = Color(hex: "00FF88")
        static let cyberBlue = Color(hex: "38BDF8")
        static let electricPurple = Color(hex: "A78BFA")
        static let hotPink = Color(hex: "FF006E")
        static let neonOrange = Color(hex: "FB923C")
    }

    enum Fonts {
        static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
        static let title = Font.system(.title, design: .default, weight: .semibold)
        static let title2 = Font.system(.title2, design: .default, weight: .semibold)
        static let headline = Font.system(.headline, design: .default)
        static let subheadline = Font.system(.subheadline, design: .default)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.caption, design: .default)
        static let code = Font.system(.body, design: .monospaced)
        static let codeCaption = Font.system(.caption, design: .monospaced)
        static let title3 = Font.system(.title3, design: .default, weight: .semibold)
        static let bodyBold = Font.system(.body, design: .default, weight: .semibold)
        static let captionBold = Font.system(.caption, design: .default, weight: .semibold)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let small: CGFloat = 8
        static let button: CGFloat = 12
        static let card: CGFloat = 16
        static let sheet: CGFloat = 20
    }

    enum Glass {
        static let overlayOpacity: Double = 0.3
        static let borderOpacity: Double = 0.08
        static let borderWidth: CGFloat = 1
        static let shadowOpacity: Double = 0.4
        static let shadowRadius: CGFloat = 12
    }
}
