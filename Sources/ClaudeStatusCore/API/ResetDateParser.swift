import Foundation

public enum ResetDateParser {
    /// Parses `2026-10-20T19:59:59.993971+00:00` as well as `2026-10-20T20:00:00+00:00`.
    /// `ISO8601DateFormatter` cannot handle six fractional digits, so the fraction is cut
    /// off and added back by hand.
    public static func parse(_ string: String) -> Date? {
        var text = string
        var fraction = 0.0
        if let dot = text.firstIndex(of: "."),
           let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            fraction = Double("0" + text[dot..<zone]) ?? 0
            text.removeSubrange(dot..<zone)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text).map { $0.addingTimeInterval(fraction) }
    }
}

extension Date {
    /// Rounded to the nearest minute, half up. `resets_at` jitters by fractions of a second
    /// between calls (19:59:59.99 vs 20:00:00.42), so truncating would split one window in two.
    public var roundedToMinute: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / 60).rounded() * 60)
    }
}

/// Stable identifier of a limit window, used in dedupe keys and to match samples to a window.
public enum WindowKey {
    public static func make(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "none" }
        return String(Int(resetsAt.roundedToMinute.timeIntervalSince1970))
    }
}
