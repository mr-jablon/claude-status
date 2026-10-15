import Foundation

/// The weekly percentage at the start of the local day (`B`), plus what is needed to
/// notice a weekly reset and to measure today's paid usage.
public struct DayBaseline: Codable, Sendable, Equatable {
    public var day: String
    public var weeklyPercent: Double
    public var weeklyResetsAt: Date?
    public var spendMinor: Int?
    /// True when the app first saw the day mid-way and `weeklyPercent` was reconstructed from local activity.
    public var estimated: Bool?

    public init(day: String, weeklyPercent: Double, weeklyResetsAt: Date?, spendMinor: Int?, estimated: Bool? = nil) {
        self.day = day
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.spendMinor = spendMinor
        self.estimated = estimated
    }
}

public enum DayState: Sendable, Equatable {
    /// Both values in percentage points of the weekly limit.
    case workday(budget: Double, used: Double)
    case weekend(used: Double)
    case unknown
}

public enum BaselineReducer {
    public static func reduce(_ baseline: DayBaseline?, weekly: LimitState?, spendMinor: Int?,
                              estimatedStart: Double? = nil, now: Date, calendar: Calendar) -> DayBaseline? {
        guard let weekly else { return baseline }
        let today = DayKey.make(now, calendar: calendar)

        guard var next = baseline, next.day == today else {
            let start = estimatedStart.map { min(weekly.percent, max(0, $0)) }
            return DayBaseline(day: today, weeklyPercent: start ?? weekly.percent,
                               weeklyResetsAt: weekly.resetsAt, spendMinor: spendMinor,
                               estimated: start == nil ? nil : true)
        }

        var windowMoved = false
        if let old = next.weeklyResetsAt, let new = weekly.resetsAt {
            windowMoved = new.timeIntervalSince(old) > 60
        }
        if windowMoved || weekly.percent < next.weeklyPercent - 0.5 {
            next.weeklyPercent = weekly.percent
        }
        if weekly.resetsAt != nil { next.weeklyResetsAt = weekly.resetsAt }

        if let spendMinor, next.spendMinor.map({ spendMinor < $0 }) ?? true {
            // first reading today, or the monthly counter started over
            next.spendMinor = spendMinor
        }
        return next
    }
}

public enum BudgetCalculator {
    /// `budget = (100 − B) × w(today) / Σ w(today … reset day)`, `used = weekly − B`.
    public static func dayState(weekly: LimitState, baseline: DayBaseline, now: Date, calendar: Calendar) -> DayState {
        let used = max(0, weekly.percent - baseline.weeklyPercent)
        guard let resetsAt = weekly.resetsAt, let today = calendar.dateInterval(of: .day, for: now) else { return .unknown }
        guard WorkdayWeights.isWorkday(now, calendar: calendar) else { return .weekend(used: used) }

        let window = WeeklyWindow(resetsAt: resetsAt)
        guard let remaining = interval(max(today.start, window.start), window.end) else { return .unknown }
        let total = WorkdayWeights.total(in: remaining, calendar: calendar)
        guard total > 0 else { return .unknown }

        let weightToday = WorkdayWeights.weight(ofDayContaining: now, within: remaining, calendar: calendar)
        let budget = max(0, 100 - baseline.weeklyPercent) * weightToday / total
        return .workday(budget: budget, used: used)
    }

    /// Weekly percentage that should be used by the end of today if the week were spread
    /// evenly over workdays.
    public static func planPercent(resetsAt: Date, now: Date, calendar: Calendar) -> Double? {
        let window = WeeklyWindow(resetsAt: resetsAt)
        guard let today = calendar.dateInterval(of: .day, for: now),
              let elapsed = interval(window.start, min(today.end, window.end)) else { return nil }
        let total = WorkdayWeights.total(in: window.interval, calendar: calendar)
        guard total > 0 else { return nil }
        return 100 * WorkdayWeights.total(in: elapsed, calendar: calendar) / total
    }
}
