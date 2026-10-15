import Foundation

public struct PacePoint: Sendable, Equatable {
    public var at: Date
    public var value: Double

    public init(at: Date, value: Double) {
        self.at = at
        self.value = value
    }
}

public enum PaceEstimator {
    public static let lookback: TimeInterval = 15 * 60
    public static let minimumSpan: TimeInterval = 12 * 60

    /// When `limit` is reached at the pace of the last 15 minutes, or `nil` when there is
    /// not enough data, usage is not growing, or the limit is already reached.
    /// `points` must come from one window (or one day) only.
    public static func eta(points: [PacePoint], limit: Double, now: Date) -> Date? {
        let recent = points.filter { now.timeIntervalSince($0.at) <= lookback }.sorted { $0.at < $1.at }
        guard let first = recent.first, let last = recent.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span >= minimumSpan else { return nil }

        let rate = (last.value - first.value) / span // per second
        let remaining = limit - last.value
        guard rate > 0, remaining > 0 else { return nil }
        return last.at.addingTimeInterval(remaining / rate)
    }
}
