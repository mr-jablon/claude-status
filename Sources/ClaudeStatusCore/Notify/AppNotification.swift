import Foundation

/// Raw values match the numbering in docs/requirements.md (F4).
public enum NotificationKind: Int, Codable, CaseIterable, Sendable {
    case sessionNear = 1, sessionReached, sessionBack, sessionForecast,
         dayNear, dayReached, weeklyPace, paidUsage, dayForecast

    public var title: String {
        switch self {
        case .sessionNear: "5h limit blízko"
        case .sessionReached: "5h limit vyčerpán"
        case .sessionBack: "5h limit je zpět"
        case .sessionForecast: "Předpověď 5h limitu"
        case .dayNear: "Denní rozpočet blízko"
        case .dayReached: "Denní rozpočet vyčerpán"
        case .weeklyPace: "Týden napřed oproti plánu"
        case .paidUsage: "Placené čerpání"
        case .dayForecast: "Předpověď denního rozpočtu"
        }
    }
}

public struct AppNotification: Sendable, Equatable {
    public let kind: NotificationKind
    /// Dedupe key; also used as the notification request identifier.
    public let key: String
    public let title: String
    public let body: String
    public let sound: Bool
    /// `nil` = deliver now; otherwise schedule for this moment.
    public let fireAt: Date?

    public init(kind: NotificationKind, key: String, title: String, body: String, sound: Bool, fireAt: Date? = nil) {
        self.kind = kind
        self.key = key
        self.title = title
        self.body = body
        self.sound = sound
        self.fireAt = fireAt
    }
}
