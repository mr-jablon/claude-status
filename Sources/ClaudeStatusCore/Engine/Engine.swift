import Foundation

public enum FetchResult: Sendable, Equatable {
    /// No request made yet (app start): show the persisted last sample.
    case pending
    case success(UsageSample)
    case tokenExpired
    case failure(String)
}

public struct StepInput: Sendable {
    public var state: PersistedState
    public var result: FetchResult
    public var now: Date
    public var settings: AppSettings
    public var calendar: Calendar
    /// Weekly percent at the start of today reconstructed from local activity; used only when today has no baseline yet.
    public var estimatedDayStart: Double?

    public init(state: PersistedState, result: FetchResult, now: Date, settings: AppSettings, calendar: Calendar,
                estimatedDayStart: Double? = nil) {
        self.estimatedDayStart = estimatedDayStart
        self.state = state
        self.result = result
        self.now = now
        self.settings = settings
        self.calendar = calendar
    }
}

public struct StepOutput: Sendable {
    public var state: PersistedState
    public var snapshot: Snapshot
    /// Already deduplicated; their keys are recorded in `state.sent`.
    public var notifications: [AppNotification]
}

/// All decisions in one pure function: baselines, budget, pace, snapshot and notifications.
public enum Engine {
    public static let staleAfter: TimeInterval = 5 * 60
    public static let sampleRetention: TimeInterval = 60 * 60
    public static let sentRetention: TimeInterval = 8 * 86_400

    public static func step(_ input: StepInput) -> StepOutput {
        var state = input.state
        let now = input.now
        let calendar = input.calendar
        var status: Snapshot.Status
        var lastError: String?

        switch input.result {
        case .pending:
            status = .loading
        case .tokenExpired:
            status = .tokenExpired
        case let .failure(message):
            lastError = message
            let recent = state.lastSuccessAt.map { now.timeIntervalSince($0) <= staleAfter } ?? false
            status = recent ? .ok : .stale(since: state.lastSuccessAt)
        case let .success(sample):
            status = .ok
            record(sample, into: &state, estimatedDayStart: input.estimatedDayStart, now: now, calendar: calendar)
        }

        let snapshot = derive(state: state, status: status, lastError: lastError, now: now, calendar: calendar)

        var notifications: [AppNotification] = []
        if case .success = input.result {
            state.sent = state.sent.filter { now.timeIntervalSince($0.value) <= sentRetention }
            let candidates = NotificationRules.evaluate(snapshot, sessionPeak: state.sessionPeak?.peak,
                                                        settings: input.settings, now: now, calendar: calendar)
            for notification in candidates where state.sent[notification.key] == nil {
                state.sent[notification.key] = now
                notifications.append(notification)
            }
        }
        return StepOutput(state: state, snapshot: snapshot, notifications: notifications)
    }

    private static func record(_ sample: UsageSample, into state: inout PersistedState,
                               estimatedDayStart: Double?, now: Date, calendar: Calendar) {
        state.lastSample = sample
        state.lastSuccessAt = now
        state.day = BaselineReducer.reduce(state.day, weekly: sample.weekly, spendMinor: sample.spend?.used.minor,
                                           estimatedStart: estimatedDayStart, now: now, calendar: calendar)

        let sessionWindow = WindowKey.make(sample.session?.resetsAt)
        state.samples.append(SamplePoint(at: now, sessionPercent: sample.session?.percent,
                                         sessionWindow: sessionWindow, weeklyPercent: sample.weekly?.percent))
        state.samples.removeAll { now.timeIntervalSince($0.at) > sampleRetention }

        if let percent = sample.session?.percent {
            if let peak = state.sessionPeak, peak.window == sessionWindow {
                state.sessionPeak?.peak = max(peak.peak, percent)
            } else {
                state.sessionPeak = SessionPeak(window: sessionWindow, peak: percent)
            }
        }
    }

    private static func derive(state: PersistedState, status: Snapshot.Status, lastError: String?,
                               now: Date, calendar: Calendar) -> Snapshot {
        guard let sample = state.lastSample else {
            let text = Format.menuBarText(status: status, session: nil, day: .unknown, hasData: false)
            return Snapshot(status: status, lastError: lastError, menuBarText: text)
        }

        let today = DayKey.make(now, calendar: calendar)
        let baseline = state.day?.day == today ? state.day : nil

        var day = DayState.unknown
        if let weekly = sample.weekly, let baseline {
            day = BudgetCalculator.dayState(weekly: weekly, baseline: baseline, now: now, calendar: calendar)
        }

        let plan = sample.weekly?.resetsAt.flatMap {
            BudgetCalculator.planPercent(resetsAt: $0, now: now, calendar: calendar)
        }

        var spendToday: Money?
        if let used = sample.spend?.used, let base = baseline?.spendMinor {
            spendToday = Money(minor: max(0, used.minor - base), exponent: used.exponent, currency: used.currency)
        }

        var sessionETA: Date?
        if let session = sample.session {
            let window = WindowKey.make(session.resetsAt)
            let points = state.samples.compactMap { point in
                point.sessionWindow == window ? point.sessionPercent.map { PacePoint(at: point.at, value: $0) } : nil
            }
            sessionETA = PaceEstimator.eta(points: points, limit: 100, now: now)
        }

        var dayETA: Date?
        if case let .workday(budget, _) = day, budget > 0, let baseline,
           let resetsAt = sample.weekly?.resetsAt, let todayStart = calendar.dateInterval(of: .day, for: now)?.start {
            let from = max(todayStart, WeeklyWindow(resetsAt: resetsAt).start)
            let points = state.samples.compactMap { point in
                point.at >= from ? point.weeklyPercent.map { PacePoint(at: point.at, value: $0) } : nil
            }
            dayETA = PaceEstimator.eta(points: points, limit: baseline.weeklyPercent + budget, now: now)
        }

        return Snapshot(
            status: status,
            fetchedAt: sample.fetchedAt,
            lastError: lastError,
            session: sample.session,
            weekly: sample.weekly,
            weeklyPlanPercent: plan,
            scoped: sample.scoped,
            day: day,
            spend: sample.spend,
            spendToday: spendToday,
            sessionETA: sessionETA,
            dayETA: dayETA,
            menuBarText: Format.menuBarText(status: status, session: sample.session, day: day, hasData: true)
        )
    }
}
