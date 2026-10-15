import Foundation
import Testing
@testable import ClaudeStatusCore

struct NotificationRulesTests {
    let now = local("2026-10-15 10:00")

    func evaluate(_ snapshot: Snapshot, peak: Double? = nil, settings: AppSettings = AppSettings(),
                  now: Date? = nil) -> [AppNotification] {
        NotificationRules.evaluate(snapshot, sessionPeak: peak, settings: settings, now: now ?? self.now, calendar: prague)
    }

    @Test func sessionNearCarriesResetTime() throws {
        let result = evaluate(Snapshot(status: .ok, session: LimitState(percent: 82, resetsAt: sessionReset)))
        let near = try #require(result.first { $0.kind == .sessionNear })
        #expect(near.title == "5h limit: 82 %")
        #expect(near.body == "Reset v 17:20 (za 7 h 20 min).")
        #expect(near.sound == false)
    }

    /// AC6: once the window reaches the warning level, "5h je zpět" is scheduled for its reset.
    @Test func sessionBackIsScheduledForReset() throws {
        let result = evaluate(Snapshot(status: .ok, session: LimitState(percent: 100, resetsAt: sessionReset)))
        let back = try #require(result.first { $0.kind == .sessionBack })
        #expect(back.fireAt == sessionReset)
        #expect(result.contains { $0.kind == .sessionReached && $0.sound })
        #expect(!result.contains { $0.kind == .sessionNear })
    }

    @Test func sessionBackUsesPeakAfterDropBelowWarning() {
        let result = evaluate(Snapshot(status: .ok, session: LimitState(percent: 40, resetsAt: sessionReset)), peak: 85)
        #expect(result.contains { $0.kind == .sessionBack })
    }

    /// AC9: the day forecast fires before the 80 % warning when the pace is high.
    @Test func dayForecastBeforeWarning() throws {
        let snapshot = Snapshot(status: .ok, day: .workday(budget: 20, used: 13), dayETA: local("2026-10-15 10:52:30"))
        let result = evaluate(snapshot)
        let forecast = try #require(result.first { $0.kind == .dayForecast })
        #expect(forecast.body == "Tímto tempem vyčerpáš dnešní rozpočet v 10:53.")
        #expect(!result.contains { $0.kind == .dayNear })
    }

    @Test func dayForecastRespectsHorizon() {
        let snapshot = Snapshot(status: .ok, day: .workday(budget: 20, used: 13), dayETA: local("2026-10-15 11:30"))
        #expect(!evaluate(snapshot).contains { $0.kind == .dayForecast })
    }

    /// AC10: no daily notifications on Saturday, session ones still fire.
    @Test func weekendSuppressesDailyNotifications() {
        let saturday = local("2026-10-17 11:00")
        let snapshot = Snapshot(status: .ok, session: LimitState(percent: 85, resetsAt: sessionReset),
                                day: .weekend(used: 30), dayETA: saturday)
        let kinds = Set(evaluate(snapshot, now: saturday).map(\.kind))
        #expect(kinds.isDisjoint(with: [.dayNear, .dayReached, .dayForecast]))
        #expect(kinds.contains(.sessionNear))
    }

    @Test func dayNearAndReached() throws {
        let near = evaluate(Snapshot(status: .ok, day: .workday(budget: 20, used: 16.5)))
        let warning = try #require(near.first { $0.kind == .dayNear })
        #expect(warning.title == "Denní rozpočet: 83 %")
        #expect(warning.body == "Zbývá 3,5 p. b. z 20.")

        let over = evaluate(Snapshot(status: .ok, day: .workday(budget: 20, used: 21)))
        #expect(over.map(\.kind) == [.dayReached])
        #expect(over.first?.sound == true)
    }

    @Test func weeklyPaceAndPaidUsage() throws {
        let snapshot = Snapshot(status: .ok, weekly: LimitState(percent: 60, resetsAt: weeklyReset), weeklyPlanPercent: 45,
                                spendToday: Money(minor: 120, exponent: 2, currency: "EUR"))
        let result = evaluate(snapshot)
        #expect(try #require(result.first { $0.kind == .weeklyPace }).body == "Využito 60 %, plán 45 %. Reset út 22:00.")
        #expect(try #require(result.first { $0.kind == .paidUsage }).body == "Dnes utraceno 1,20 € z extra usage.")
    }

    @Test func disabledKindIsSkipped() {
        var settings = AppSettings()
        settings.enabled.remove(.sessionNear)
        let result = evaluate(Snapshot(status: .ok, session: LimitState(percent: 82, resetsAt: sessionReset)),
                              settings: settings)
        #expect(!result.contains { $0.kind == .sessionNear })
    }

    @Test func onlyReachedKindsPlaySound() {
        let snapshot = Snapshot(status: .ok, session: LimitState(percent: 100, resetsAt: sessionReset),
                                weekly: LimitState(percent: 90, resetsAt: weeklyReset), weeklyPlanPercent: 40,
                                day: .workday(budget: 10, used: 12), spendToday: Money(minor: 5, exponent: 2, currency: "EUR"))
        let sounding = Set(evaluate(snapshot).filter(\.sound).map(\.kind))
        #expect(sounding == [.sessionReached, .dayReached])
    }
}

struct FormatTests {
    @Test func menuBarVariants() {
        let session = LimitState(percent: 82, resetsAt: sessionReset)
        #expect(Format.menuBarText(status: .ok, session: session, day: .workday(budget: 20, used: 12.8), hasData: true)
                == "◐ 5h 82%  den 64%")
        #expect(Format.menuBarText(status: .stale(since: nil), session: session, day: .unknown, hasData: true)
                == "◐ 5h 82%  den – ⚠")
        #expect(Format.menuBarText(status: .tokenExpired, session: session, day: .unknown, hasData: true)
                == "◐ ⚠ přihlášení")
        #expect(Format.menuBarText(status: .loading, session: nil, day: .unknown, hasData: false) == "◐ …")
        #expect(Format.menuBarText(status: .ok, session: session, day: .workday(budget: 0, used: 2), hasData: true)
                == "◐ 5h 82%  den >100%")
    }

    @Test func czechTimePreposition() {
        #expect(Format.at(local("2026-10-15 12:20"), calendar: prague) == "ve 12:20")
        #expect(Format.at(local("2026-10-15 14:35"), calendar: prague) == "ve 14:35")
        #expect(Format.at(local("2026-10-15 15:10"), calendar: prague) == "v 15:10")
        #expect(Format.at(local("2026-10-15 9:05"), calendar: prague) == "v 9:05")
    }

    @Test func numbersAndMoney() {
        #expect(Format.points(3) == "3")
        #expect(Format.points(20.4255) == "20,4")
        #expect(Format.money(Money(minor: 235, exponent: 2, currency: "EUR")) == "2,35 €")
        #expect(Format.relative(local("2026-10-15 12:20"), now: local("2026-10-15 12:06")) == "za 14 min")
        #expect(Format.relative(local("2026-10-15 14:11"), now: local("2026-10-15 12:06")) == "za 2 h 5 min")
        #expect(Format.weekdayTime(weeklyReset, calendar: prague) == "út 22:00")
    }
}
