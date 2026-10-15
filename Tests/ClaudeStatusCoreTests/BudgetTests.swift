import Foundation
import Testing
@testable import ClaudeStatusCore

struct WorkdayWeightsTests {
    @Test func currentWeekWeights() {
        let window = WeeklyWindow(resetsAt: weeklyReset).interval
        let days = (13...20).map { local("2026-10-\($0) 12:00") }
        let weights = days.map { WorkdayWeights.weight(ofDayContaining: $0, within: window, calendar: prague) }

        let expected = [2.0 / 24, 1, 1, 1, 0, 0, 1, 22.0 / 24]
        for (weight, value) in zip(weights, expected) {
            #expect(abs(weight - value) < 1e-9)
        }
        #expect(abs(WorkdayWeights.total(in: window, calendar: prague) - 5) < 1e-9)
    }

    /// The window ending 2026-10-27 spans the end of DST (Sun 25 Oct has 25 h).
    @Test func dstWeekLosesAnHourOfWorkdays() {
        let reset = utc("2026-10-27T20:00:00Z") // 21:00 CET
        #expect(Format.time(reset, calendar: prague) == "21:00")
        let total = WorkdayWeights.total(in: WeeklyWindow(resetsAt: reset).interval, calendar: prague)
        #expect(abs(total - (4 + 23.0 / 24)) < 1e-9)
    }
}

struct BudgetCalculatorTests {
    func baseline(_ day: String, _ percent: Double, resetsAt: Date = weeklyReset) -> DayBaseline {
        DayBaseline(day: day, weeklyPercent: percent, weeklyResetsAt: resetsAt, spendMinor: nil)
    }

    func budget(_ now: Date, b: Double, weekly: Double) -> (budget: Double, used: Double)? {
        let state = BudgetCalculator.dayState(weekly: LimitState(percent: weekly, resetsAt: weeklyReset),
                                              baseline: baseline(DayKey.make(now, calendar: prague), b),
                                              now: now, calendar: prague)
        guard case let .workday(budget, used) = state else { return nil }
        return (budget, used)
    }

    /// Example from F3: Thursday, week at 20 % → 80 / 3.92 ≈ 20.4.
    @Test func thursdayExample() throws {
        let result = try #require(budget(local("2026-10-15 09:00"), b: 20, weekly: 20))
        #expect(abs(result.budget - 80 / (3 + 22.0 / 24)) < 1e-9)
        #expect(Format.points(result.budget) == "20,4")
    }

    /// AC3: overspending on Friday shrinks the remaining workdays proportionally.
    @Test func fridayOverspendShrinksFollowingWorkdays() throws {
        let friday = try #require(budget(local("2026-10-16 10:00"), b: 40, weekly: 40))
        let remainingAfterFriday = 1 + 22.0 / 24 // Mon + most of Tue
        #expect(abs(friday.budget - 60 / (1 + remainingAfterFriday)) < 1e-9)

        let weekendStart = 40 + friday.budget + 5
        let saturday = BudgetCalculator.dayState(weekly: LimitState(percent: weekendStart, resetsAt: weeklyReset),
                                                 baseline: baseline("2026-10-17", weekendStart),
                                                 now: local("2026-10-17 12:00"), calendar: prague)
        #expect(saturday == .weekend(used: 0))

        let monday = try #require(budget(local("2026-10-19 09:00"), b: weekendStart, weekly: weekendStart))
        #expect(abs(monday.budget - (friday.budget - 5 / remainingAfterFriday)) < 1e-9)
    }

    /// AC4: Saturday usage shows as weekend usage and comes out of Monday's budget.
    @Test func saturdayUsageReducesMonday() throws {
        let saturday = BudgetCalculator.dayState(weekly: LimitState(percent: 53, resetsAt: weeklyReset),
                                                 baseline: baseline("2026-10-17", 50),
                                                 now: local("2026-10-17 15:00"), calendar: prague)
        #expect(saturday == .weekend(used: 3))
        #expect(Format.menuBarText(status: .ok, session: nil, day: saturday, hasData: true) == "◐ 5h –  víkend +3 p. b.")

        let withWeekendUse = try #require(budget(local("2026-10-19 09:00"), b: 53, weekly: 53))
        let without = try #require(budget(local("2026-10-19 09:00"), b: 50, weekly: 50))
        #expect(abs((without.budget - withWeekendUse.budget) - 3 / (1 + 22.0 / 24)) < 1e-9)
    }

    /// AC5: the weekly reset at Tue 22:00 re-baselines and budgets from 100 % the same evening.
    @Test func weeklyResetRebaselinesSameEvening() throws {
        let now = local("2026-10-20 22:01")
        let nextReset = utc("2026-10-27T20:00:00Z")
        let before = baseline("2026-10-20", 95)
        let after = try #require(BaselineReducer.reduce(before, weekly: LimitState(percent: 0.5, resetsAt: nextReset),
                                                        spendMinor: nil, now: now, calendar: prague))
        #expect(after.weeklyPercent == 0.5)
        #expect(after.weeklyResetsAt == nextReset)

        let state = BudgetCalculator.dayState(weekly: LimitState(percent: 0.5, resetsAt: nextReset),
                                              baseline: after, now: now, calendar: prague)
        guard case let .workday(budget, used) = state else { Issue.record("expected workday"); return }
        #expect(used == 0)
        #expect(abs(budget - 99.5 * (2.0 / 24) / (4 + 23.0 / 24)) < 1e-9)
    }

    @Test func planThroughEndOfToday() throws {
        let plan = try #require(BudgetCalculator.planPercent(resetsAt: weeklyReset, now: local("2026-10-15 12:00"),
                                                             calendar: prague))
        #expect(abs(plan - 100 * (2.0 / 24 + 2) / 5) < 1e-9)
    }
}

struct BaselineReducerTests {
    let now = local("2026-10-15 09:00")

    @Test func firstReadingOfTheDaySetsBaseline() throws {
        let old = DayBaseline(day: "2026-10-14", weeklyPercent: 10, weeklyResetsAt: weeklyReset, spendMinor: 100)
        let next = try #require(BaselineReducer.reduce(old, weekly: LimitState(percent: 25, resetsAt: weeklyReset),
                                                       spendMinor: 120, now: now, calendar: prague))
        #expect(next == DayBaseline(day: "2026-10-15", weeklyPercent: 25, weeklyResetsAt: weeklyReset, spendMinor: 120))
    }

    @Test func laterReadingsKeepBaseline() throws {
        let start = DayBaseline(day: "2026-10-15", weeklyPercent: 25, weeklyResetsAt: weeklyReset, spendMinor: 120)
        let jittered = weeklyReset.addingTimeInterval(0.4)
        let next = try #require(BaselineReducer.reduce(start, weekly: LimitState(percent: 31, resetsAt: jittered),
                                                       spendMinor: 150, now: now, calendar: prague))
        #expect(next.weeklyPercent == 25)
        #expect(next.spendMinor == 120)
    }

    @Test func monthlySpendRolloverRebaselinesSpend() throws {
        let start = DayBaseline(day: "2026-10-15", weeklyPercent: 25, weeklyResetsAt: weeklyReset, spendMinor: 480)
        let next = try #require(BaselineReducer.reduce(start, weekly: LimitState(percent: 26, resetsAt: weeklyReset),
                                                       spendMinor: 0, now: now, calendar: prague))
        #expect(next.spendMinor == 0)
    }
}

struct PaceEstimatorTests {
    let now = local("2026-10-15 10:00")

    /// AC9 numbers: 11 → 13 p. b. over 15 min is 8 p. b./h; 7 p. b. left to a limit of 20.
    @Test func ac9Projection() throws {
        let points = [PacePoint(at: local("2026-10-15 09:45"), value: 11), PacePoint(at: now, value: 13)]
        let eta = try #require(PaceEstimator.eta(points: points, limit: 20, now: now))
        #expect(eta == local("2026-10-15 10:52:30"))
    }

    @Test func tooLittleData() {
        let points = [PacePoint(at: local("2026-10-15 09:50"), value: 11), PacePoint(at: now, value: 13)]
        #expect(PaceEstimator.eta(points: points, limit: 20, now: now) == nil)
    }

    @Test func flatOrFallingUsage() {
        let start = local("2026-10-15 09:45")
        #expect(PaceEstimator.eta(points: [PacePoint(at: start, value: 13), PacePoint(at: now, value: 13)],
                                  limit: 20, now: now) == nil)
        #expect(PaceEstimator.eta(points: [PacePoint(at: start, value: 14), PacePoint(at: now, value: 13)],
                                  limit: 20, now: now) == nil)
    }

    @Test func ignoresPointsOlderThanLookback() {
        let points = [PacePoint(at: local("2026-10-15 09:30"), value: 5), PacePoint(at: local("2026-10-15 09:55"), value: 12),
                      PacePoint(at: now, value: 13)]
        #expect(PaceEstimator.eta(points: points, limit: 20, now: now) == nil) // only 5 min of usable data
    }
}
