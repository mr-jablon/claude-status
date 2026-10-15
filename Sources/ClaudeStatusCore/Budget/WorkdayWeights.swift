import Foundation

/// The weekly limit window: a fixed 7 × 24 h of absolute time ending at `resets_at`.
/// Its local start and end shift by an hour across DST.
public struct WeeklyWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(resetsAt: Date) {
        end = resetsAt
        start = resetsAt.addingTimeInterval(-7 * 86_400)
    }

    public var interval: DateInterval { DateInterval(start: start, end: end) }
}

public enum WorkdayWeights {
    /// Mon–Fri are workdays; Sat and Sun weigh 0.
    public static func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday … 7 = Saturday
        return weekday != 1 && weekday != 7
    }

    /// The part of the day containing `date` that is a workday inside `range`, divided by
    /// that day's real length (23 or 25 h on DST days).
    public static func weight(ofDayContaining date: Date, within range: DateInterval, calendar: Calendar) -> Double {
        guard isWorkday(date, calendar: calendar),
              let day = calendar.dateInterval(of: .day, for: date),
              let overlap = day.intersection(with: range) else { return 0 }
        return overlap.duration / day.duration
    }

    /// Sum of the weights of all days that intersect `range`.
    public static func total(in range: DateInterval, calendar: Calendar) -> Double {
        var sum = 0.0
        var cursor = calendar.startOfDay(for: range.start)
        while cursor < range.end {
            sum += weight(ofDayContaining: cursor, within: range, calendar: calendar)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return sum
    }
}

/// Local calendar day as `yyyy-MM-dd`, used for daily baselines and dedupe keys.
public enum DayKey {
    public static func make(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// `DateInterval(start:end:)` traps when `end < start`.
func interval(_ start: Date, _ end: Date) -> DateInterval? {
    end >= start ? DateInterval(start: start, end: end) : nil
}
