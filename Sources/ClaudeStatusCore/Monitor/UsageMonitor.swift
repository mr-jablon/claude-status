import Foundation
import Observation
import os

/// Runs the polling loop: token → fetch → `Engine.step` → save → notify.
/// All decisions live in `Engine`; this class only does the IO around it.
@MainActor @Observable
public final class UsageMonitor {
    public static let interval: TimeInterval = 60
    public static let maxBackoff: TimeInterval = 900

    public private(set) var snapshot: Snapshot
    public private(set) var lastAttemptAt: Date?
    public var settings: AppSettings {
        didSet { store.saveSettings(settings) }
    }

    @ObservationIgnored private var state: PersistedState
    @ObservationIgnored private let tokens: any TokenProviding
    @ObservationIgnored private let client: any UsageFetching
    @ObservationIgnored private let notifier: any Notifying
    @ObservationIgnored private let store: any StateStoring
    @ObservationIgnored private let activity: (any ActivityEstimating)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var isTicking = false
    @ObservationIgnored private(set) var consecutiveFailures = 0
    @ObservationIgnored private var retryAfter: TimeInterval?

    private static let log = Logger(subsystem: "local.ClaudeStatus", category: "monitor")

    public init(tokens: any TokenProviding, client: any UsageFetching, notifier: any Notifying,
                store: any StateStoring, activity: (any ActivityEstimating)? = nil, now: @escaping @Sendable () -> Date = { Date() },
                calendar: Calendar = .current) {
        self.tokens = tokens
        self.client = client
        self.notifier = notifier
        self.store = store
        self.activity = activity
        self.now = now
        self.calendar = calendar
        let state = store.loadState()
        let settings = store.loadSettings()
        self.state = state
        self.settings = settings
        snapshot = Engine.step(StepInput(state: state, result: .pending, now: now(),
                                         settings: settings, calendar: calendar)).snapshot
    }

    public func start() {
        guard loop == nil else { return }
        runLoop()
    }

    /// At most one request per 60 s, also for manual refreshes.
    public var canRefresh: Bool {
        !isTicking && (lastAttemptAt.map { now().timeIntervalSince($0) >= Self.interval } ?? true)
    }

    public func refreshNow() {
        guard canRefresh else { return }
        loop?.cancel()
        runLoop()
    }

    public func handleWake() {
        refreshNow()
    }

    /// One fetch and step without saving or notifying, for `--dump`.
    public func dryRun() async -> StepOutput {
        let result = await fetch()
        return Engine.step(StepInput(state: state, result: result, now: now(), settings: settings, calendar: calendar,
                                     estimatedDayStart: await estimateDayStart(for: result)))
    }

    /// A day first seen mid-way (app started late) has no morning baseline; rebuild it from local activity.
    private func estimateDayStart(for result: FetchResult) async -> Double? {
        guard let activity, case let .success(sample) = result, let weekly = sample.weekly,
              let resetsAt = weekly.resetsAt else { return nil }
        let current = now()
        let dayStart = calendar.startOfDay(for: current)
        guard state.day?.day != DayKey.make(current, calendar: calendar) else { return nil }
        let windowStart = resetsAt.addingTimeInterval(-7 * 86_400)
        guard dayStart > windowStart,
              let share = await activity.todayShare(windowStart: windowStart, dayStart: dayStart, until: current)
        else { return nil }
        return (weekly.percent * (1 - min(1, max(0, share)))).rounded()
    }

    var nextDelay: TimeInterval {
        if let retryAfter { return max(Self.interval, retryAfter) }
        guard consecutiveFailures > 0 else { return Self.interval }
        return min(Self.maxBackoff, Self.interval * pow(2, Double(consecutiveFailures)))
    }

    private func runLoop() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(self.nextDelay))
            }
        }
    }

    func tick() async {
        guard !isTicking else { return }
        isTicking = true
        defer { isTicking = false }

        lastAttemptAt = now()
        let result = await fetch()
        if case .failure = result { consecutiveFailures += 1 } else { consecutiveFailures = 0 }

        let estimate = await estimateDayStart(for: result)
        let output = Engine.step(StepInput(state: state, result: result, now: now(), settings: settings,
                                           calendar: calendar, estimatedDayStart: estimate))
        state = output.state
        snapshot = output.snapshot
        store.saveState(state)
        Self.log.info("tick: \(output.snapshot.menuBarText, privacy: .public), notifications: \(output.notifications.count)")

        if !output.notifications.isEmpty {
            await notifier.deliver(output.notifications)
        }
    }

    private func fetch() async -> FetchResult {
        retryAfter = nil
        let token: OAuthToken
        do {
            token = try await tokens.readToken()
        } catch {
            Self.log.error("token: \(String(describing: error), privacy: .public)")
            return .tokenExpired
        }
        guard token.expiresAt > now() else { return .tokenExpired }

        do {
            return .success(UsageMapper.map(try await client.fetchUsage(token: token.accessToken), fetchedAt: now()))
        } catch UsageFetchError.unauthorized {
            // Claude Code may have rotated the token since it was read; retry once with a new one.
            guard let fresh = try? await tokens.readToken(), fresh.accessToken != token.accessToken,
                  fresh.expiresAt > now() else { return .tokenExpired }
            do {
                return .success(UsageMapper.map(try await client.fetchUsage(token: fresh.accessToken), fetchedAt: now()))
            } catch {
                return failure(error)
            }
        } catch {
            return failure(error)
        }
    }

    private func failure(_ error: any Error) -> FetchResult {
        Self.log.error("fetch: \(String(describing: error), privacy: .public)")
        guard let error = error as? UsageFetchError else { return .failure(error.localizedDescription) }
        switch error {
        case .unauthorized:
            return .tokenExpired
        case let .rateLimited(after):
            retryAfter = after
            return .failure(error.message)
        default:
            return .failure(error.message)
        }
    }
}
