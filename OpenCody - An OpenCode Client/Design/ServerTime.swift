import Foundation

// MARK: - ServerTime

/// Server timestamps arrive in seconds or milliseconds; one shared formatter renders them.
enum ServerTime {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func date(_ raw: Double) -> Date {
        // Values beyond year ~33658 in seconds are milliseconds.
        Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
    }

    /// "5 min ago"; empty for a missing (zero) timestamp.
    static func relative(_ raw: Double) -> String {
        guard raw > 0 else { return "" }
        return relative.localizedString(for: date(raw), relativeTo: .now)
    }
}
