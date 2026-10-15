import Foundation

/// Everything the UI shows. Rebuilt by `Engine.step` on every tick.
public struct Snapshot: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case loading
        case ok
        case stale(since: Date?)
        case tokenExpired
    }

    public var status: Status
    public var fetchedAt: Date?
    public var lastError: String?
    public var session: LimitState?
    public var weekly: LimitState?
    public var weeklyPlanPercent: Double?
    public var scoped: [ScopedLimitState]
    public var day: DayState
    public var spend: Spend?
    public var spendToday: Money?
    public var sessionETA: Date?
    public var dayETA: Date?
    public var menuBarText: String

    public init(status: Status, fetchedAt: Date? = nil, lastError: String? = nil,
                session: LimitState? = nil, weekly: LimitState? = nil, weeklyPlanPercent: Double? = nil,
                scoped: [ScopedLimitState] = [], day: DayState = .unknown, spend: Spend? = nil,
                spendToday: Money? = nil, sessionETA: Date? = nil, dayETA: Date? = nil, menuBarText: String = "") {
        self.status = status
        self.fetchedAt = fetchedAt
        self.lastError = lastError
        self.session = session
        self.weekly = weekly
        self.weeklyPlanPercent = weeklyPlanPercent
        self.scoped = scoped
        self.day = day
        self.spend = spend
        self.spendToday = spendToday
        self.sessionETA = sessionETA
        self.dayETA = dayETA
        self.menuBarText = menuBarText
    }

    public var hasData: Bool { fetchedAt != nil }
}
