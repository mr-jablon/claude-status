import Foundation

public struct SamplePoint: Codable, Sendable, Equatable {
    public var at: Date
    public var sessionPercent: Double?
    /// `WindowKey` of the 5-hour window the session value belongs to.
    public var sessionWindow: String
    public var weeklyPercent: Double?
}

public struct SessionPeak: Codable, Sendable, Equatable {
    public var window: String
    public var peak: Double
}

/// Everything that has to survive a restart. A cache of derived data: when its shape
/// changes, bump the storage key instead of migrating.
public struct PersistedState: Codable, Sendable, Equatable {
    public var day: DayBaseline?
    /// Last hour of readings, for the pace estimates.
    public var samples: [SamplePoint] = []
    /// Highest session percentage seen in the current 5-hour window (for #3).
    public var sessionPeak: SessionPeak?
    /// Dedupe key → when it was sent.
    public var sent: [String: Date] = [:]
    public var lastSample: UsageSample?
    public var lastSuccessAt: Date?

    public init() {}
}
