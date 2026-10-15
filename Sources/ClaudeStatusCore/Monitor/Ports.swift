import Foundation

/// Reads the Claude Code OAuth token. Deliberately read-only: there is no way to write
/// or refresh the token through this port.
public protocol TokenProviding: Sendable {
    func readToken() async throws -> OAuthToken
}

public enum UsageFetchError: Error, Sendable, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case decoding
    case network(String)

    public var message: String {
        switch self {
        case .unauthorized: "Token byl odmítnut (401)"
        case .rateLimited: "API omezilo dotazy (429)"
        case let .http(code): "Chyba API (HTTP \(code))"
        case .decoding: "Odpovědi API nejde porozumět"
        case let .network(detail): "Síť: \(detail)"
        }
    }
}

public protocol UsageFetching: Sendable {
    func fetchUsage(token: String) async throws -> UsageResponseDTO
}

public protocol Notifying: Sendable {
    func deliver(_ notifications: [AppNotification]) async
}

public protocol StateStoring: Sendable {
    func loadState() -> PersistedState
    func saveState(_ state: PersistedState)
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings)
}

/// Reconstructs how much of the current weekly window's activity happened today, from local data.
public protocol ActivityEstimating: Sendable {
    /// Share (0…1) of the activity in `[windowStart, until]` that falls in `[dayStart, until]`;
    /// nil when there is nothing to base an estimate on.
    func todayShare(windowStart: Date, dayStart: Date, until: Date) async -> Double?
}
