import SwiftUI

extension UIColor {
    convenience init(hex: String) {
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
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

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

    /// Builds a color that resolves differently in light and dark interface styles.
    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static func adaptive(light: String, dark: String) -> Color {
        adaptive(light: UIColor(hex: light), dark: UIColor(hex: dark))
    }
}

enum Theme {
    enum Colors {
        /// Neutral ink used to tint light-mode hairlines, fills and separators.
        private static let lightInk = UIColor(hex: "312D2D")

        // MARK: Surfaces & text
        // Dark mode values are the original hardcoded palette and must not drift.
        // Light mode follows the opencode.ai paper palette.
        static let deepBlack = Color.adaptive(light: "F2F1F0", dark: "0C0C0C")
        static let carbon = Color.adaptive(light: "FFFFFF", dark: "141414")
        static let graphite = Color.adaptive(light: "E9E7E6", dark: "1E1E1E")
        static let slate = Color.adaptive(light: "DAD9D9", dark: "2D2D2D")
        static let smoke = Color.adaptive(light: "A3A09E", dark: "404040")
        static let silver = Color.adaptive(light: "6E6B69", dark: "8B8B8B")
        static let cloud = Color.adaptive(light: "312D2D", dark: "E5E5E5")

        // MARK: Accents
        static let neonGreen = Color.adaptive(light: "028500", dark: "00FF88")
        static let cyberBlue = Color.adaptive(light: "0270AD", dark: "38BDF8")
        static let electricPurple = Color.adaptive(light: "6B45D0", dark: "A78BFA")
        static let hotPink = Color.adaptive(light: "D6006C", dark: "FF006E")
        static let neonOrange = Color.adaptive(light: "B45309", dark: "FB923C")
        /// JavaScript brand yellow, deepened in light mode so it stays legible on paper.
        static let javascriptYellow = Color.adaptive(light: "927C00", dark: "F7DF1E")

        // MARK: Strokes & fills
        // Drop-in replacements for the former Color.white.opacity(...) hairlines,
        // which disappear against a paper background.
        static let hairline = Color.adaptive(light: lightInk.withAlphaComponent(0.12),
                                             dark: UIColor(white: 1, alpha: 0.06))
        static let border = Color.adaptive(light: lightInk.withAlphaComponent(0.14),
                                           dark: UIColor(white: 1, alpha: 0.08))
        static let borderStrong = Color.adaptive(light: lightInk.withAlphaComponent(0.20),
                                                 dark: UIColor(white: 1, alpha: 0.12))
        static let fillSubtle = Color.adaptive(light: lightInk.withAlphaComponent(0.05),
                                               dark: UIColor(white: 1, alpha: 0.04))
        static let fillMuted = Color.adaptive(light: lightInk.withAlphaComponent(0.06),
                                              dark: UIColor(white: 1, alpha: 0.06))
        static let fillStrong = Color.adaptive(light: lightInk.withAlphaComponent(0.08),
                                               dark: UIColor(white: 1, alpha: 0.08))

        // MARK: Glass, shadow, scrim
        /// Tint laid over `.ultraThinMaterial` panels: darkens in dark mode, brightens on paper.
        static let glassFill = Color.adaptive(light: UIColor(white: 1, alpha: 0.60),
                                              dark: UIColor(white: 0, alpha: 0.30))
        static let glassFillSoft = Color.adaptive(light: UIColor(white: 1, alpha: 0.45),
                                                  dark: UIColor(white: 0, alpha: 0.20))
        static let shadow = Color.adaptive(light: UIColor(white: 0, alpha: 0.14),
                                           dark: UIColor(white: 0, alpha: 0.40))
        static let scrim = Color.adaptive(light: UIColor(white: 0, alpha: 0.30),
                                          dark: UIColor(white: 0, alpha: 0.60))

        // MARK: Labels on tinted accent surfaces
        static let onPrimaryAccent = Color.adaptive(light: "024E78", dark: "FFFFFF")
        static let onDestructiveAccent = Color.adaptive(light: "8A0046", dark: "FFFFFF")
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

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
