import ClaudeStatusCore
import Foundation

/// An explicit suite, so `swift run ClaudeStatus --dump` reads the same data as the app.
/// It must differ from the bundle identifier: a suite named after the app's own bundle ID
/// does not work.
struct UserDefaultsStateStore: StateStoring {
    static let suiteName = "local.ClaudeStatus.state"
    private static let stateKey = "state.v1"
    private static let settingsKey = "settings.v1"

    private var defaults: UserDefaults { UserDefaults(suiteName: Self.suiteName) ?? .standard }

    func loadState() -> PersistedState { load(PersistedState.self, Self.stateKey) ?? PersistedState() }
    func saveState(_ state: PersistedState) { save(state, Self.stateKey) }
    func loadSettings() -> AppSettings { load(AppSettings.self, Self.settingsKey) ?? AppSettings() }
    func saveSettings(_ settings: AppSettings) { save(settings, Self.settingsKey) }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
