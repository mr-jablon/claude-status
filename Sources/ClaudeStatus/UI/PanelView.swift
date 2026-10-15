import ClaudeStatusCore
import SwiftUI

struct MenuBarLabel: View {
    let monitor: UsageMonitor

    var body: some View {
        Text(monitor.snapshot.menuBarText)
    }
}

struct PanelView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.showingSettings {
                SettingsView(model: model, monitor: model.monitor)
            } else {
                OverviewView(model: model)
            }
        }
        .padding(14)
        .frame(width: 330)
    }
}

struct OverviewView: View {
    let model: AppModel
    private let calendar = Calendar.current

    var body: some View {
        let monitor = model.monitor
        let snapshot = monitor.snapshot
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 12) {
                Text("Claude limity").font(.headline)
                statusLine(snapshot, now: now)

                if let session = snapshot.session {
                    LimitRow(title: "5h limit", fraction: session.percent / 100,
                             value: Format.percent(session.percent),
                             detail: sessionDetail(session, eta: snapshot.sessionETA, now: now),
                             color: color(session.percent, warn: monitor.settings.sessionWarn))
                }
                dayRow(snapshot)
                if let weekly = snapshot.weekly {
                    LimitRow(title: "Týden", fraction: weekly.percent / 100,
                             marker: snapshot.weeklyPlanPercent.map { $0 / 100 },
                             value: Format.percent(weekly.percent),
                             detail: weeklyDetail(weekly, plan: snapshot.weeklyPlanPercent),
                             color: color(weekly.percent - (snapshot.weeklyPlanPercent ?? 0),
                                          warn: monitor.settings.weeklyPaceMargin, over: 100))
                }
                ForEach(snapshot.scoped, id: \.name) { scoped in
                    LimitRow(title: "Týden – \(scoped.name)", fraction: scoped.limit.percent / 100,
                             value: Format.percent(scoped.limit.percent),
                             detail: scoped.limit.resetsAt.map { "reset \(Format.weekdayTime($0, calendar: calendar))" } ?? "",
                             color: color(scoped.limit.percent, warn: 80))
                }
                if let spend = snapshot.spend {
                    spendRow(spend, today: snapshot.spendToday)
                }
                if model.notificationsDenied {
                    Label("Oznámení jsou v Nastavení systému zakázaná.", systemImage: "bell.slash")
                        .font(.caption).foregroundStyle(.orange)
                }

                Divider()
                HStack {
                    Button("Obnovit") { monitor.refreshNow() }.disabled(!monitor.canRefresh)
                    Button("Nastavení") { model.showingSettings = true }
                    Spacer()
                    Button("Ukončit") { NSApp.terminate(nil) }
                }
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ snapshot: Snapshot, now: Date) -> some View {
        let error = snapshot.lastError.map { " · \($0)" } ?? ""
        switch snapshot.status {
        case .loading:
            Text("Načítám…").font(.caption).foregroundStyle(.secondary)
        case .ok:
            Text("Aktualizováno \(snapshot.fetchedAt.map { Format.time($0, calendar: calendar) } ?? "–")\(error)")
                .font(.caption).foregroundStyle(.secondary)
        case let .stale(since):
            Text("⚠ Data jsou stará (\(since.map { Format.ago($0, now: now) } ?? "zatím žádná"))\(error)")
                .font(.caption).foregroundStyle(.orange)
        case .tokenExpired:
            Text("⚠ Přihlášení vypršelo – otevři Claude Code, ten ho obnoví.")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func dayRow(_ snapshot: Snapshot) -> some View {
        switch snapshot.day {
        case let .workday(budget, used):
            let percent = budget > 0 ? Format.dayPercent(budget: budget, used: used) : (used > 0 ? 100 : 0)
            let eta = snapshot.dayETA.map { " · tempem vyčerpáš \(Format.at($0, calendar: calendar))" } ?? ""
            LimitRow(title: "Dnes", fraction: percent / 100,
                     value: budget > 0 ? Format.percent(percent) : "–",
                     detail: "\(Format.points(used)) z \(Format.points(budget)) p. b.\(eta)",
                     color: color(percent, warn: model.monitor.settings.dayWarn))
        case let .weekend(used):
            Text("Víkend: +\(Format.points(used)) p. b., ubírá z pracovních dnů")
                .font(.subheadline)
        case .unknown:
            EmptyView()
        }
    }

    private func spendRow(_ spend: Spend, today: Money?) -> some View {
        let limit = spend.limit.map { " z \(Format.money($0))" } ?? ""
        let todayText = today.map { "dnes \(Format.money($0))" } ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Placené čerpání").font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Format.money(spend.used))\(limit)").font(.subheadline.monospacedDigit())
            }
            if !todayText.isEmpty {
                Text(todayText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sessionDetail(_ session: LimitState, eta: Date?, now: Date) -> String {
        var parts: [String] = []
        if let resetsAt = session.resetsAt {
            parts.append("reset \(Format.time(resetsAt, calendar: calendar)) (\(Format.relative(resetsAt, now: now)))")
        }
        if let eta { parts.append("tempem limit \(Format.at(eta, calendar: calendar))") }
        return parts.joined(separator: " · ")
    }

    private func weeklyDetail(_ weekly: LimitState, plan: Double?) -> String {
        var parts: [String] = []
        if let plan { parts.append("plán \(Format.percent(plan))") }
        if let resetsAt = weekly.resetsAt { parts.append("reset \(Format.weekdayTime(resetsAt, calendar: calendar))") }
        return parts.joined(separator: " · ")
    }

    private func color(_ value: Double, warn: Double, over: Double = 100) -> Color {
        if value >= over { return .red }
        if value >= warn { return .orange }
        return .accentColor
    }
}

struct LimitRow: View {
    let title: String
    let fraction: Double
    var marker: Double?
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(value).font(.subheadline.monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: geo.size.width * clamp(fraction))
                    if let marker {
                        Rectangle().fill(.primary)
                            .frame(width: 2, height: geo.size.height + 4)
                            .offset(x: geo.size.width * clamp(marker) - 1)
                    }
                }
            }
            .frame(height: 6)
            if !detail.isEmpty {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}
