import AppKit
import ClaudeStatusCore
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            Task { @MainActor in
                await Dump.run()
                exit(0)
            }
            dispatchMain()
        }
        ClaudeStatusApp.main()
    }
}

struct ClaudeStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: AppModel.shared)
        } label: {
            MenuBarLabel(monitor: AppModel.shared.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.launch()
    }
}

/// `--dump`: one fetch, printed to stdout. Saves nothing and sends no notifications,
/// so it works from `swift run` without an app bundle.
@MainActor
enum Dump {
    struct SilentNotifier: Notifying {
        func deliver(_ notifications: [AppNotification]) async {}
    }

    static func run() async {
        let monitor = UsageMonitor(tokens: SecurityCLITokenProvider(), client: URLSessionUsageClient(),
                                   notifier: SilentNotifier(), store: UserDefaultsStateStore(),
                               activity: ClaudeCodeLogActivity())
        let output = await monitor.dryRun()
        let s = output.snapshot
        let cal = Calendar.current
        let now = Date()

        print("Stav:    \(s.status)\(s.lastError.map { " – \($0)" } ?? "")")
        print("Lišta:   \(s.menuBarText)")
        if let session = s.session {
            let reset = session.resetsAt.map { "reset \(Format.time($0, calendar: cal)) (\(Format.relative($0, now: now)))" } ?? ""
            let eta = s.sessionETA.map { ", tempem limit \(Format.at($0, calendar: cal))" } ?? ""
            print("5h:      \(Format.percent(session.percent)), \(reset)\(eta)")
        }
        if let weekly = s.weekly {
            let plan = s.weeklyPlanPercent.map { ", plán \(Format.percent($0))" } ?? ""
            let reset = weekly.resetsAt.map { ", reset \(Format.weekdayTime($0, calendar: cal))" } ?? ""
            print("Týden:   \(Format.percent(weekly.percent))\(plan)\(reset)")
        }
        for scoped in s.scoped {
            print("Týden \(scoped.name): \(Format.percent(scoped.limit.percent))")
        }
        switch s.day {
        case let .workday(budget, used):
            let eta = s.dayETA.map { ", tempem vyčerpáš \(Format.at($0, calendar: cal))" } ?? ""
            print("Dnes:    \(Format.points(used)) z \(Format.points(budget)) p. b.\(eta)")
        case let .weekend(used):
            print("Víkend:  +\(Format.points(used)) p. b.")
        case .unknown:
            print("Dnes:    –")
        }
        if let spend = s.spend {
            let limit = spend.limit.map { " z \(Format.money($0))" } ?? ""
            let today = s.spendToday.map { ", dnes \(Format.money($0))" } ?? ""
            print("Placené: \(Format.money(spend.used))\(limit)\(today)")
        }
        let pending = output.notifications.map { "  [#\($0.kind.rawValue)] \($0.title) – \($0.body)" }
        print("Oznámení, která by odešla:" + (pending.isEmpty ? " žádná" : "\n" + pending.joined(separator: "\n")))
    }
}
