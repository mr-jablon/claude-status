import Foundation

/// Decides which notifications the current snapshot calls for. Dedupe against already sent
/// keys happens in `Engine`; this only builds candidates.
public enum NotificationRules {
    public static func evaluate(_ snapshot: Snapshot, sessionPeak: Double?, settings: AppSettings,
                                now: Date, calendar: Calendar) -> [AppNotification] {
        var out: [AppNotification] = []
        let today = DayKey.make(now, calendar: calendar)

        func add(_ kind: NotificationKind, window: String, title: String, body: String, fireAt: Date? = nil) {
            guard settings.enabled.contains(kind) else { return }
            let sound = kind == .sessionReached || kind == .dayReached
            out.append(AppNotification(kind: kind, key: "\(kind.rawValue)|\(window)",
                                       title: title, body: body, sound: sound, fireAt: fireAt))
        }

        if let session = snapshot.session {
            let window = WindowKey.make(session.resetsAt)
            let reset = session.resetsAt.map {
                "\(Format.at($0, calendar: calendar)) (\(Format.relative($0, now: now)))"
            }

            if session.percent >= settings.sessionWarn && session.percent < 100 {
                add(.sessionNear, window: window, title: "5h limit: \(Format.percent(session.percent))",
                    body: reset.map { "Reset \($0)." } ?? "")
            }
            if session.percent >= 100 {
                add(.sessionReached, window: window, title: "5h limit vyčerpán",
                    body: reset.map { "Znovu k dispozici \($0)." } ?? "")
            }
            if let resetsAt = session.resetsAt, max(sessionPeak ?? 0, session.percent) >= settings.sessionWarn {
                add(.sessionBack, window: window, title: "5h limit je zpět", body: "Můžeš pokračovat.", fireAt: resetsAt)
            }
            if let eta = snapshot.sessionETA, let resetsAt = session.resetsAt, eta < resetsAt, session.percent < 100 {
                add(.sessionForecast, window: window, title: "5h limit: tempo",
                    body: "Tímto tempem narazíš na limit \(Format.at(eta, calendar: calendar)), reset je \(Format.at(resetsAt, calendar: calendar)).")
            }
        }

        if case let .workday(budget, used) = snapshot.day {
            if budget > 0 && used >= budget * settings.dayWarn / 100 && used < budget {
                add(.dayNear, window: today,
                    title: "Denní rozpočet: \(Format.percent(Format.dayPercent(budget: budget, used: used)))",
                    body: "Zbývá \(Format.points(budget - used)) p. b. z \(Format.points(budget)).")
            }
            if used > 0 && used >= budget {
                add(.dayReached, window: today, title: "Denní rozpočet vyčerpán",
                    body: "Další čerpání ubírá ze zbývajících pracovních dnů.")
            }
            if let eta = snapshot.dayETA, used < budget,
               eta.timeIntervalSince(now) <= settings.dayForecastHorizonMinutes * 60 {
                add(.dayForecast, window: today, title: "Denní rozpočet: tempo",
                    body: "Tímto tempem vyčerpáš dnešní rozpočet \(Format.at(eta, calendar: calendar)).")
            }
        }

        if let weekly = snapshot.weekly, let plan = snapshot.weeklyPlanPercent,
           weekly.percent - plan > settings.weeklyPaceMargin {
            let reset = weekly.resetsAt.map { " Reset \(Format.weekdayTime($0, calendar: calendar))." } ?? ""
            add(.weeklyPace, window: today, title: "Týden: napřed oproti plánu",
                body: "Využito \(Format.percent(weekly.percent)), plán \(Format.percent(plan)).\(reset)")
        }

        if let spent = snapshot.spendToday, spent.minor > 0 {
            add(.paidUsage, window: today, title: "Placené čerpání",
                body: "Dnes utraceno \(Format.money(spent)) z extra usage.")
        }

        return out
    }
}
