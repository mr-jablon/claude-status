import ClaudeStatusCore
import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let monitor: UsageMonitor
    var notificationsDenied = false
    var loginItemMessage: String?
    var showingSettings = false

    @ObservationIgnored private let notifier = UserNotificationsNotifier()

    private init() {
        monitor = UsageMonitor(tokens: SecurityCLITokenProvider(), client: URLSessionUsageClient(),
                               notifier: notifier, store: UserDefaultsStateStore(),
                               activity: ClaudeCodeLogActivity())
    }

    func launch() {
        notifier.activate()
        Task {
            notificationsDenied = !(await notifier.requestAuthorization())
        }
        syncLoginItem()
        WakeObserver.observe { [weak self] in self?.monitor.handleWake() }
        monitor.start()
    }

    func sendTestNotification() {
        let test = AppNotification(kind: .sessionNear, key: "test|\(Date().timeIntervalSince1970)",
                                   title: "Zkušební oznámení", body: "Oznámení z Claude Status fungují.", sound: true)
        Task { await notifier.deliver([test]) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        monitor.settings.launchAtLogin = enabled
        syncLoginItem()
    }

    private func syncLoginItem() {
        let wanted = monitor.settings.launchAtLogin
        guard LoginItem.isInstalledLocation else {
            loginItemMessage = wanted ? "Funguje jen z ~/Applications (scripts/bundle.sh --install)." : nil
            return
        }
        do {
            if wanted != (LoginItem.status == .enabled) { try LoginItem.set(wanted) }
            loginItemMessage = LoginItem.status == .requiresApproval
                ? "Povol v Nastavení systému → Obecné → Položky při přihlášení." : nil
        } catch {
            loginItemMessage = error.localizedDescription
        }
    }
}
