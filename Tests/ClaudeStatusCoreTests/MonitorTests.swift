import Foundation
import Testing
@testable import ClaudeStatusCore

actor FakeTokens: TokenProviding {
    private var queue: [OAuthToken]
    private(set) var reads = 0

    init(_ tokens: OAuthToken...) { queue = tokens }

    func readToken() async throws -> OAuthToken {
        reads += 1
        return queue.count > 1 ? queue.removeFirst() : queue[0]
    }
}

actor FakeClient: UsageFetching {
    private var queue: [Result<UsageResponseDTO, UsageFetchError>]
    private(set) var requestedTokens: [String] = []

    init(_ results: Result<UsageResponseDTO, UsageFetchError>...) { queue = results }

    func fetchUsage(token: String) async throws -> UsageResponseDTO {
        requestedTokens.append(token)
        return try (queue.count > 1 ? queue.removeFirst() : queue[0]).get()
    }
}

actor FakeNotifier: Notifying {
    private(set) var delivered: [AppNotification] = []
    func deliver(_ notifications: [AppNotification]) async { delivered += notifications }
}

struct FakeActivity: ActivityEstimating {
    var share: Double?
    func todayShare(windowStart: Date, dayStart: Date, until: Date) async -> Double? { share }
}

final class FakeStore: StateStoring, @unchecked Sendable {
    var state = PersistedState()
    var settings = AppSettings()
    var stateSaves = 0

    func loadState() -> PersistedState { state }
    func saveState(_ state: PersistedState) { self.state = state; stateSaves += 1 }
    func loadSettings() -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) { self.settings = settings }
}

final class TestClock: @unchecked Sendable {
    var now = local("2026-10-15 10:00")
}

func usage(session: Double, weekly: Double = 30) throws -> UsageResponseDTO {
    try decode("""
    {"limits": [
      {"kind": "session", "percent": \(session), "resets_at": "2026-10-15T15:20:00+00:00"},
      {"kind": "weekly_all", "percent": \(weekly), "resets_at": "2026-10-20T20:00:00+00:00"}
    ]}
    """)
}

@MainActor
struct UsageMonitorTests {
    let clock = TestClock()
    let store = FakeStore()
    let notifier = FakeNotifier()

    func token(_ value: String, validFor seconds: TimeInterval = 3600) -> OAuthToken {
        OAuthToken(accessToken: value, expiresAt: clock.now.addingTimeInterval(seconds))
    }

    func makeMonitor(_ tokens: FakeTokens, _ client: FakeClient) -> UsageMonitor {
        let clock = clock
        return UsageMonitor(tokens: tokens, client: client, notifier: notifier, store: store,
                            now: { clock.now }, calendar: prague)
    }

    @Test func lateStartRebuildsMorningBaselineFromActivity() async throws {
        let clock = clock
        let monitor = UsageMonitor(tokens: FakeTokens(token("a")), client: FakeClient(.success(try usage(session: 5, weekly: 30))),
                                   notifier: notifier, store: store, activity: FakeActivity(share: 0.4),
                                   now: { clock.now }, calendar: prague)
        await monitor.tick()

        #expect(store.state.day?.weeklyPercent == 18)
        #expect(store.state.day?.estimated == true)
        guard case let .workday(_, used) = monitor.snapshot.day else { Issue.record("not a workday"); return }
        #expect(used == 12)
    }

    @Test func existingBaselineIsNotReestimated() async throws {
        store.state.day = DayBaseline(day: DayKey.make(clock.now, calendar: prague), weeklyPercent: 25,
                                      weeklyResetsAt: nil, spendMinor: nil)
        let clock = clock
        let monitor = UsageMonitor(tokens: FakeTokens(token("a")), client: FakeClient(.success(try usage(session: 5, weekly: 30))),
                                   notifier: notifier, store: store, activity: FakeActivity(share: 0.4),
                                   now: { clock.now }, calendar: prague)
        await monitor.tick()
        #expect(store.state.day?.weeklyPercent == 25)
    }

    @Test func successfulTickSavesAndNotifies() async throws {
        let client = FakeClient(.success(try usage(session: 85)))
        let monitor = makeMonitor(FakeTokens(token("a")), client)
        await monitor.tick()

        #expect(monitor.snapshot.status == .ok)
        #expect(monitor.snapshot.session?.percent == 85)
        #expect(store.stateSaves == 1)
        #expect(await client.requestedTokens == ["a"])
        #expect(await notifier.delivered.map(\.kind).contains(.sessionNear))
    }

    /// AC7: with an expired token the API is not called at all.
    @Test func expiredTokenSkipsRequest() async throws {
        let client = FakeClient(.success(try usage(session: 10)))
        let monitor = makeMonitor(FakeTokens(token("a", validFor: -60)), client)
        await monitor.tick()

        #expect(monitor.snapshot.status == .tokenExpired)
        #expect(await client.requestedTokens.isEmpty)
    }

    @Test func unauthorizedRetriesOnceWithRotatedToken() async throws {
        let client = FakeClient(.failure(.unauthorized), .success(try usage(session: 10)))
        let monitor = makeMonitor(FakeTokens(token("old"), token("new")), client)
        await monitor.tick()

        #expect(monitor.snapshot.status == .ok)
        #expect(await client.requestedTokens == ["old", "new"])
    }

    @Test func unauthorizedWithSameTokenGivesUp() async throws {
        let client = FakeClient(.failure(.unauthorized))
        let monitor = makeMonitor(FakeTokens(token("a")), client)
        await monitor.tick()

        #expect(monitor.snapshot.status == .tokenExpired)
        #expect(await client.requestedTokens == ["a"])
    }

    @Test func backoffDoublesUpToCapAndResets() async throws {
        let failure = Result<UsageResponseDTO, UsageFetchError>.failure(.http(500))
        let client = FakeClient(failure, failure, failure, failure, failure, .success(try usage(session: 10)))
        let monitor = makeMonitor(FakeTokens(token("a")), client)

        var delays: [TimeInterval] = []
        for _ in 0..<6 {
            await monitor.tick()
            delays.append(monitor.nextDelay)
        }
        #expect(delays == [120, 240, 480, 900, 900, 60])
    }

    @Test func rateLimitHonoursRetryAfterButAtLeastAMinute() async throws {
        let client = FakeClient(.failure(.rateLimited(retryAfter: 300)), .failure(.rateLimited(retryAfter: 10)))
        let monitor = makeMonitor(FakeTokens(token("a")), client)

        await monitor.tick()
        #expect(monitor.nextDelay == 300)
        await monitor.tick()
        #expect(monitor.nextDelay == 60)
    }

    @Test func manualRefreshAtMostOncePerMinute() async throws {
        let monitor = makeMonitor(FakeTokens(token("a")), FakeClient(.success(try usage(session: 10))))
        #expect(monitor.canRefresh)
        await monitor.tick()
        #expect(!monitor.canRefresh)
        clock.now = clock.now.addingTimeInterval(61)
        #expect(monitor.canRefresh)
    }

    @Test func startShowsPersistedValues() throws {
        let earlier = clock.now.addingTimeInterval(-300)
        store.state.lastSample = sample(at: earlier, session: 42, weekly: 30)
        let monitor = makeMonitor(FakeTokens(token("a")), FakeClient(.success(try usage(session: 10))))

        #expect(monitor.snapshot.status == .loading)
        #expect(monitor.snapshot.session?.percent == 42)
    }
}
