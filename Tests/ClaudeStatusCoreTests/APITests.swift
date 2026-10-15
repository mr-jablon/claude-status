import Foundation
import Testing
@testable import ClaudeStatusCore

struct ResetDateParserTests {
    @Test func parsesMicrosecondsAndPlainSeconds() throws {
        let micro = try #require(ResetDateParser.parse("2026-10-20T19:59:59.993971+00:00"))
        let plain = try #require(ResetDateParser.parse("2026-10-20T20:00:00+00:00"))
        #expect(abs(micro.timeIntervalSince(plain) + 0.006029) < 0.0001)
    }

    @Test func jitterAcrossTheMinuteMapsToOneWindow() throws {
        // Two real readings of the same weekly reset, 0.4 s apart across a minute boundary.
        let a = try #require(ResetDateParser.parse("2026-10-20T19:59:59.993971+00:00"))
        let b = try #require(ResetDateParser.parse("2026-10-20T20:00:00.418563+00:00"))
        #expect(a.roundedToMinute == utc("2026-10-20T20:00:00Z"))
        #expect(WindowKey.make(a) == WindowKey.make(b))
    }

    @Test func rejectsGarbage() {
        #expect(ResetDateParser.parse("tomorrow") == nil)
    }
}

struct UsageMapperTests {
    let fetchedAt = local("2026-10-15 12:40")

    @Test func mapsTheLiveResponse() throws {
        let dto = try JSONDecoder().decode(UsageResponseDTO.self, from: fixture("usage-full"))
        let sample = UsageMapper.map(dto, fetchedAt: fetchedAt)

        #expect(sample.session?.percent == 4)
        #expect(sample.session?.resetsAt?.roundedToMinute == utc("2026-10-15T15:20:00Z"))
        #expect(sample.weekly?.percent == 29)
        #expect(sample.weekly?.resetsAt?.roundedToMinute == weeklyReset)
        #expect(sample.scoped.map(\.name) == ["Fable"])
        #expect(sample.spend?.used == Money(minor: 235, exponent: 2, currency: "EUR"))
        #expect(sample.spend?.used.value == 2.35)
        #expect(sample.spend?.limit?.minor == 500)
    }

    /// AC8: without `limits[]` the flat objects give the same session, weekly and spend.
    @Test func flatOnlyResponseStillWorks() throws {
        let full = UsageMapper.map(try JSONDecoder().decode(UsageResponseDTO.self, from: fixture("usage-full")),
                                   fetchedAt: fetchedAt)
        let flat = UsageMapper.map(try JSONDecoder().decode(UsageResponseDTO.self, from: fixture("usage-flat-only")),
                                   fetchedAt: fetchedAt)

        #expect(flat.session == full.session)
        #expect(flat.weekly == full.weekly)
        #expect(flat.spend == full.spend)
        #expect(flat.scoped.isEmpty)
    }

    @Test func wrongTypeEmptiesOnlyThatValue() throws {
        let full = UsageMapper.map(try JSONDecoder().decode(UsageResponseDTO.self, from: fixture("usage-full")),
                                   fetchedAt: fetchedAt)
        let broken = UsageMapper.map(try JSONDecoder().decode(UsageResponseDTO.self, from: fixture("usage-type-mismatch")),
                                     fetchedAt: fetchedAt)

        #expect(broken.session == full.session) // from five_hour
        #expect(broken.weekly == full.weekly)   // limits[] still usable
        #expect(broken.spend == full.spend)     // from extra_usage
        #expect(broken.scoped == full.scoped)
    }

    @Test func emptyObjectDecodes() throws {
        let sample = UsageMapper.map(try decode("{}"), fetchedAt: fetchedAt)
        #expect(sample.session == nil && sample.weekly == nil && sample.spend == nil)
    }
}

struct OAuthTokenTests {
    @Test func readsMillisecondExpiry() throws {
        let json = #"{"mcpOAuth":{},"claudeAiOauth":{"accessToken":"t","refreshToken":"r","expiresAt":1792076276361}}"#
        let token = try OAuthToken.parse(keychainJSON: Data(json.utf8))
        #expect(token.accessToken == "t")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 1_792_076_276.361))
    }

    @Test func missingClaudeEntryThrows() {
        #expect(throws: OAuthToken.ParseError.self) {
            try OAuthToken.parse(keychainJSON: Data(#"{"mcpOAuth":{}}"#.utf8))
        }
    }
}
