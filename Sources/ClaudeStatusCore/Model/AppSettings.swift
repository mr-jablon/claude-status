import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var sessionWarn: Double = 80
    public var dayWarn: Double = 80
    public var weeklyPaceMargin: Double = 10
    public var dayForecastHorizonMinutes: Double = 60
    public var enabled: Set<NotificationKind> = Set(NotificationKind.allCases)
    public var launchAtLogin: Bool = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case sessionWarn, dayWarn, weeklyPaceMargin, dayForecastHorizonMinutes, enabled, launchAtLogin
    }

    /// Missing keys fall back to defaults, so adding a setting does not reset the others.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        sessionWarn = c.lenient(Double.self, .sessionWarn) ?? defaults.sessionWarn
        dayWarn = c.lenient(Double.self, .dayWarn) ?? defaults.dayWarn
        weeklyPaceMargin = c.lenient(Double.self, .weeklyPaceMargin) ?? defaults.weeklyPaceMargin
        dayForecastHorizonMinutes = c.lenient(Double.self, .dayForecastHorizonMinutes) ?? defaults.dayForecastHorizonMinutes
        enabled = c.lenient(Set<NotificationKind>.self, .enabled) ?? defaults.enabled
        launchAtLogin = c.lenient(Bool.self, .launchAtLogin) ?? defaults.launchAtLogin
    }
}
