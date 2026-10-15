import Foundation
import Testing
@testable import ClaudeStatusCore

struct EngineTests {
    let settings = AppSettings()

    func step(_ state: PersistedState, _ result: FetchResult, at now: Date) -> StepOutput {
        Engine.step(StepInput(state: state, result: result, now: now, settings: settings, calendar: prague))
    }

    /// AC1: 79 → 81 → 85 → 90 % gives exactly one "near" notification, also across a restart.
    @Test func sessionNearOncePerWindowAcrossRestart() throws {
        var state = PersistedState()
        var near = 0
        for (minute, percent) in [79.0, 81, 85, 90].enumerated() {
            let now = local("2026-10-15 10:00").addingTimeInterval(Double(minute) * 60)
            let output = step(state, .success(sample(at: now, session: percent, weekly: 30)), at: now)
            near += output.notifications.filter { $0.kind == .sessionNear }.count
            state = output.state
        }
        #expect(near == 1)

        let restored = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        let now = local("2026-10-15 10:05")
        let afterRestart = step(restored, .success(sample(at: now, session: 90, weekly: 30)), at: now)
        #expect(afterRestart.notifications.isEmpty)
    }

    /// AC2: budget 20, used 16.5 → "den 83%" and the day warning.
    @Test func dayWarningAndMenuBarText() {
        let now = local("2026-10-15 10:00")
        let reset = local("2026-10-17 00:00") // Thu + Fri left → budget = (100 − 60) / 2
        var state = PersistedState()
        state.day = DayBaseline(day: "2026-10-15", weeklyPercent: 60, weeklyResetsAt: reset, spendMinor: nil)

        let output = step(state, .success(sample(at: now, session: 10, weekly: 76.5, weeklyResetsAt: reset)), at: now)
        #expect(output.snapshot.day == .workday(budget: 20, used: 16.5))
        #expect(output.snapshot.menuBarText == "◐ 5h 10%  den 83%")
        #expect(output.notifications.map(\.kind).contains(.dayNear))
    }

    /// AC7 (engine part): an expired token shows a login state and sends nothing.
    @Test func expiredToken() {
        let output = step(PersistedState(), .tokenExpired, at: local("2026-10-15 10:00"))
        #expect(output.snapshot.status == .tokenExpired)
        #expect(output.snapshot.menuBarText == "◐ ⚠ přihlášení")
        #expect(output.notifications.isEmpty)
    }

    @Test func failureKeepsLastValuesAndTurnsStale() {
        let first = local("2026-10-15 10:00")
        let ok = step(PersistedState(), .success(sample(at: first, session: 50, weekly: 30)), at: first)

        let soon = step(ok.state, .failure("Síť"), at: first.addingTimeInterval(120))
        #expect(soon.snapshot.status == .ok)
        #expect(soon.snapshot.lastError == "Síť")
        #expect(soon.snapshot.session?.percent == 50)

        let late = step(ok.state, .failure("Síť"), at: first.addingTimeInterval(600))
        #expect(late.snapshot.status == .stale(since: first))
        #expect(late.snapshot.menuBarText.hasSuffix("⚠"))
        #expect(late.notifications.isEmpty)
    }

    @Test func pendingRestoresLastSample() {
        let first = local("2026-10-15 10:00")
        let ok = step(PersistedState(), .success(sample(at: first, session: 50, weekly: 30)), at: first)
        let restored = step(ok.state, .pending, at: first.addingTimeInterval(30))
        #expect(restored.snapshot.status == .loading)
        #expect(restored.snapshot.session?.percent == 50)
    }

    @Test func paidUsageOncePerDay() {
        let first = local("2026-10-15 10:00")
        let morning = step(PersistedState(), .success(sample(at: first, weekly: 30, spendMinor: 235)), at: first)
        #expect(morning.snapshot.spendToday?.minor == 0)

        let later = first.addingTimeInterval(3600)
        let spent = step(morning.state, .success(sample(at: later, weekly: 31, spendMinor: 355)), at: later)
        #expect(spent.snapshot.spendToday?.minor == 120)
        #expect(spent.notifications.map(\.kind) == [.paidUsage])

        let evenLater = later.addingTimeInterval(600)
        let again = step(spent.state, .success(sample(at: evenLater, weekly: 31, spendMinor: 400)), at: evenLater)
        #expect(again.notifications.isEmpty)
    }

    @Test func sessionForecastFromSamples() throws {
        var state = PersistedState()
        var output: StepOutput?
        for minute in stride(from: 0, through: 15, by: 1) {
            let now = local("2026-10-15 10:00").addingTimeInterval(Double(minute) * 60)
            output = step(state, .success(sample(at: now, session: 40 + Double(minute), weekly: 30)), at: now)
            state = output!.state
        }
        let last = try #require(output)
        // 1 %/min from 55 % → 100 % at 10:15 + 45 min, before the 17:20 reset.
        #expect(last.snapshot.sessionETA == local("2026-10-15 11:00"))
        #expect(last.state.notifications(of: .sessionForecast) == 1)
    }

    @Test func oldSentKeysArePruned() {
        var state = PersistedState()
        state.sent["5|2026-10-01"] = local("2026-10-01 10:00")
        let now = local("2026-10-15 10:00")
        let output = step(state, .success(sample(at: now, session: 10, weekly: 30)), at: now)
        #expect(output.state.sent["5|2026-10-01"] == nil)
    }
}

extension PersistedState {
    func notifications(of kind: NotificationKind) -> Int {
        sent.keys.filter { $0.hasPrefix("\(kind.rawValue)|") }.count
    }
}
