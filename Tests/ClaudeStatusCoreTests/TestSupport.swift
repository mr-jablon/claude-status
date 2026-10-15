import Foundation
import Testing
@testable import ClaudeStatusCore

let prague: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar
}()

/// `local("2026-10-15 10:00")` in Europe/Prague.
func local(_ text: String) -> Date {
    let parts = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" }).map { Int($0)! }
    var components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])
    components.second = parts.count > 5 ? parts[5] : 0
    return prague.date(from: components)!
}

/// `utc("2026-10-20T20:00:00Z")`
func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func decode(_ json: String) throws -> UsageResponseDTO {
    try JSONDecoder().decode(UsageResponseDTO.self, from: Data(json.utf8))
}

/// Weekly limit resets on Tue 2026-10-20 at 22:00 Prague time (CEST).
let weeklyReset = utc("2026-10-20T20:00:00Z")
/// 5-hour window ending Thu 2026-10-15 at 17:20 Prague time.
let sessionReset = utc("2026-10-15T15:20:00Z")

func sample(at: Date, session: Double? = nil, weekly: Double? = nil, weeklyResetsAt: Date = weeklyReset,
            spendMinor: Int? = nil) -> UsageSample {
    UsageSample(
        fetchedAt: at,
        session: session.map { LimitState(percent: $0, resetsAt: sessionReset) },
        weekly: weekly.map { LimitState(percent: $0, resetsAt: weeklyResetsAt) },
        spend: spendMinor.map { Spend(used: Money(minor: $0, exponent: 2, currency: "EUR"),
                                      limit: Money(minor: 500, exponent: 2, currency: "EUR")) }
    )
}
