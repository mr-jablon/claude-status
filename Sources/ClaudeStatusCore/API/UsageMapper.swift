import Foundation

public enum UsageMapper {
    /// Prefers the structured `limits[]`; falls back to the flat `five_hour` / `seven_day`
    /// objects, and from `spend` to `extra_usage`.
    public static func map(_ dto: UsageResponseDTO, fetchedAt: Date) -> UsageSample {
        let limits = dto.limits ?? []

        func limit(kind: String) -> LimitState? {
            guard let entry = limits.first(where: { $0.kind == kind && $0.percent != nil }) else { return nil }
            return LimitState(percent: entry.percent!, resetsAt: entry.resetsAt.flatMap(ResetDateParser.parse))
        }

        func window(_ window: WindowDTO?) -> LimitState? {
            guard let utilization = window?.utilization else { return nil }
            return LimitState(percent: utilization, resetsAt: window?.resetsAt.flatMap(ResetDateParser.parse))
        }

        let scoped = limits
            .filter { $0.kind == "weekly_scoped" && $0.percent != nil }
            .map { entry in
                ScopedLimitState(
                    name: entry.modelName ?? "model",
                    limit: LimitState(percent: entry.percent!, resetsAt: entry.resetsAt.flatMap(ResetDateParser.parse))
                )
            }

        return UsageSample(
            fetchedAt: fetchedAt,
            session: limit(kind: "session") ?? window(dto.fiveHour),
            weekly: limit(kind: "weekly_all") ?? window(dto.sevenDay),
            scoped: scoped,
            spend: spend(dto)
        )
    }

    private static func spend(_ dto: UsageResponseDTO) -> Spend? {
        if let spend = dto.spend, spend.enabled != false,
           let used = spend.used.flatMap(money) {
            return Spend(used: used, limit: spend.limit.flatMap(money))
        }
        if let extra = dto.extraUsage, extra.isEnabled != false, let usedCredits = extra.usedCredits {
            let exponent = extra.decimalPlaces ?? 2
            let currency = extra.currency ?? "EUR"
            return Spend(
                used: Money(minor: Int(usedCredits.rounded()), exponent: exponent, currency: currency),
                limit: extra.monthlyLimit.map { Money(minor: Int($0.rounded()), exponent: exponent, currency: currency) }
            )
        }
        return nil
    }

    private static func money(_ dto: MoneyDTO) -> Money? {
        guard let minor = dto.amountMinor else { return nil }
        return Money(minor: minor, exponent: dto.exponent ?? 2, currency: dto.currency ?? "EUR")
    }
}
