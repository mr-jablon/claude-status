import Foundation

public struct LimitState: Codable, Sendable, Equatable {
    /// 0–100.
    public var percent: Double
    public var resetsAt: Date?

    public init(percent: Double, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public struct ScopedLimitState: Codable, Sendable, Equatable {
    public var name: String
    public var limit: LimitState

    public init(name: String, limit: LimitState) {
        self.name = name
        self.limit = limit
    }
}

/// An amount in minor units: `minor: 235, exponent: 2` is 2.35.
public struct Money: Codable, Sendable, Equatable {
    public var minor: Int
    public var exponent: Int
    public var currency: String

    public init(minor: Int, exponent: Int, currency: String) {
        self.minor = minor
        self.exponent = exponent
        self.currency = currency
    }

    public var value: Double { Double(minor) / pow(10, Double(exponent)) }
}

public struct Spend: Codable, Sendable, Equatable {
    public var used: Money
    public var limit: Money?

    public init(used: Money, limit: Money?) {
        self.used = used
        self.limit = limit
    }
}

/// One successful reading of the usage endpoint, independent of its JSON shape.
public struct UsageSample: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    public var session: LimitState?
    public var weekly: LimitState?
    public var scoped: [ScopedLimitState]
    public var spend: Spend?

    public init(fetchedAt: Date, session: LimitState?, weekly: LimitState?,
                scoped: [ScopedLimitState] = [], spend: Spend? = nil) {
        self.fetchedAt = fetchedAt
        self.session = session
        self.weekly = weekly
        self.scoped = scoped
        self.spend = spend
    }
}
