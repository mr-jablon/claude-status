import Foundation
import Testing
@testable import ClaudeStatusCore

struct MoneyTests {
    @Test func minorUnitsRespectExponent() {
        #expect(Money(minor: 235, exponent: 2, currency: "EUR").value == 2.35)
        #expect(Money(minor: 500, exponent: 0, currency: "CZK").value == 500)
        #expect(Money(minor: 1, exponent: 3, currency: "EUR").value == 0.001)
    }

    @Test func currencySymbols() {
        #expect(Format.money(Money(minor: 12_000, exponent: 2, currency: "CZK")) == "120,00 Kč")
        #expect(Format.money(Money(minor: 5, exponent: 2, currency: "USD")) == "0,05 $")
        #expect(Format.money(Money(minor: 7, exponent: 0, currency: "XYZ")) == "7 XYZ")
    }
}

struct AppSettingsTests {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test func emptyObjectGivesDefaults() throws {
        #expect(try decode("{}") == AppSettings())
    }

    @Test func missingKeysKeepTheirDefaults() throws {
        let settings = try decode(#"{"dayWarn": 70}"#)
        #expect(settings.dayWarn == 70)
        #expect(settings.sessionWarn == AppSettings().sessionWarn)
        #expect(settings.enabled == AppSettings().enabled)
    }

    @Test func wrongTypeResetsOnlyThatKey() throws {
        let settings = try decode(#"{"sessionWarn": "high", "dayWarn": 70, "launchAtLogin": false}"#)
        #expect(settings.sessionWarn == AppSettings().sessionWarn)
        #expect(settings.dayWarn == 70)
        #expect(settings.launchAtLogin == false)
    }

    @Test func unknownNotificationKindFallsBackToAllEnabled() throws {
        let settings = try decode(#"{"enabled": [1, 99]}"#)
        #expect(settings.enabled == Set(NotificationKind.allCases))
    }

    @Test func roundTrip() throws {
        var settings = AppSettings()
        settings.sessionWarn = 65
        settings.enabled = [.sessionReached, .dayReached]
        settings.launchAtLogin = false
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }
}

struct PersistedStateTests {
    @Test func roundTripKeepsEverything() throws {
        var state = PersistedState()
        state.day = DayBaseline(day: "2026-10-15", weeklyPercent: 20, weeklyResetsAt: weeklyReset, spendMinor: 100)
        state.samples = [SamplePoint(at: local("2026-10-15 10:00"), sessionPercent: 30,
                                     sessionWindow: "w1", weeklyPercent: 21)]
        state.sessionPeak = SessionPeak(window: "w1", peak: 82)
        state.sent = ["1|w1|80": local("2026-10-15 10:05")]
        state.lastSample = sample(at: local("2026-10-15 10:00"), session: 30, weekly: 21, spendMinor: 235)
        state.lastSuccessAt = local("2026-10-15 10:00")

        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(PersistedState.self, from: data) == state)
    }
}

struct NotificationKindTests {
    @Test func numberingMatchesRequirements() {
        #expect(NotificationKind.allCases.map(\.rawValue) == Array(1...9))
    }

    @Test func everyKindHasAUniqueTitle() {
        let titles = NotificationKind.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
    }
}

struct SnapshotTests {
    @Test func hasDataOnlyAfterAFetch() {
        #expect(Snapshot(status: .loading).hasData == false)
        #expect(Snapshot(status: .ok, fetchedAt: local("2026-10-15 10:00")).hasData)
    }
}

struct FormatEdgeCaseTests {
    @Test func timeRoundsToNearestMinute() {
        #expect(Format.time(local("2026-10-15 12:19:45"), calendar: prague) == "12:20")
        #expect(Format.time(local("2026-10-15 12:20:20"), calendar: prague) == "12:20")
        #expect(Format.time(local("2026-10-15 0:05"), calendar: prague) == "0:05")
    }

    @Test func relativeCoversPastAndWholeHours() {
        let now = local("2026-10-15 12:00")
        #expect(Format.relative(now, now: now) == "teď")
        #expect(Format.relative(local("2026-10-15 11:00"), now: now) == "teď")
        #expect(Format.relative(local("2026-10-15 14:00"), now: now) == "za 2 h")
    }

    @Test func agoCoversRecentAndHours() {
        let now = local("2026-10-15 12:00")
        #expect(Format.ago(local("2026-10-15 11:59:30"), now: now) == "právě teď")
        #expect(Format.ago(local("2026-10-15 11:48"), now: now) == "před 12 min")
        #expect(Format.ago(local("2026-10-15 10:55"), now: now) == "před 1 h 5 min")
    }

    @Test func percentRounding() {
        #expect(Format.compactPercent(81.5) == "82%")
        #expect(Format.compactPercent(81.4) == "81%")
        #expect(Format.percent(0) == "0 %")
        #expect(Format.dayPercent(budget: 20, used: 16.5) == 82.5)
    }

    @Test func pointsDropNegligibleDecimals() {
        #expect(Format.points(0.04) == "0")
        #expect(Format.points(2.96) == "3")
        #expect(Format.points(1.5) == "1,5")
    }
}
