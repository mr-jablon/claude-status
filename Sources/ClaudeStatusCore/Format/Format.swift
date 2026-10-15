import Foundation

/// User-facing Czech strings. Kept in Core so tests cover them; views only display them.
public enum Format {
    public static let icon = "◐"

    /// `◐ 5h 82%  den 64%`
    public static func menuBarText(status: Snapshot.Status, session: LimitState?, day: DayState, hasData: Bool) -> String {
        if status == .tokenExpired { return "\(icon) ⚠ přihlášení" }
        guard hasData else { return status == .loading ? "\(icon) …" : "\(icon) 5h –" }

        let sessionPart = session.map { "5h \(compactPercent($0.percent))" } ?? "5h –"
        let dayPart: String
        switch day {
        case let .workday(budget, used):
            if budget > 0 {
                dayPart = "den \(compactPercent(dayPercent(budget: budget, used: used)))"
            } else {
                dayPart = used > 0 ? "den >100%" : "den –"
            }
        case let .weekend(used):
            dayPart = "víkend +\(points(used)) p. b."
        case .unknown:
            dayPart = "den –"
        }
        let staleMark = if case .stale = status { " ⚠" } else { "" }
        return "\(icon) \(sessionPart)  \(dayPart)\(staleMark)"
    }

    /// `used / budget` in percent; multiplies before dividing so 16.5 / 20 gives exactly 82.5.
    public static func dayPercent(budget: Double, used: Double) -> Double {
        used * 100 / budget
    }

    /// `82%`
    public static func compactPercent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// `82 %`
    public static func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }

    /// `3,4`, or `3` when the decimal would be zero.
    public static func points(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.05 { return String(Int(value.rounded())) }
        return decimal(value, digits: 1)
    }

    /// `2,35 €`
    public static func money(_ money: Money) -> String {
        let symbol = switch money.currency {
        case "EUR": "€"
        case "CZK": "Kč"
        case "USD": "$"
        default: money.currency
        }
        return "\(decimal(money.value, digits: max(0, money.exponent))) \(symbol)"
    }

    /// `12:20`, rounded to the nearest minute.
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date.roundedToMinute)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `ve 12:20`, `v 15:10` – Czech picks the preposition by how the hour is pronounced.
    public static func at(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date.roundedToMinute)
        let preposition = [2, 3, 4, 12, 13, 14, 20, 21, 22, 23].contains(hour) ? "ve" : "v"
        return "\(preposition) \(time(date, calendar: calendar))"
    }

    /// `út 22:00`
    public static func weekdayTime(_ date: Date, calendar: Calendar) -> String {
        let names = ["ne", "po", "út", "st", "čt", "pá", "so"]
        let weekday = calendar.component(.weekday, from: date.roundedToMinute)
        return "\(names[(weekday - 1) % 7]) \(time(date, calendar: calendar))"
    }

    /// `za 14 min`, `za 2 h 5 min`
    public static func relative(_ date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded())
        guard minutes > 0 else { return "teď" }
        guard minutes >= 60 else { return "za \(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "za \(hours) h" : "za \(hours) h \(rest) min"
    }

    /// `před 12 min`
    public static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int((now.timeIntervalSince(date) / 60).rounded(.down))
        guard minutes > 0 else { return "právě teď" }
        guard minutes >= 60 else { return "před \(minutes) min" }
        return "před \(minutes / 60) h \(minutes % 60) min"
    }

    static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }
}
