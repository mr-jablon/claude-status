import Foundation

// Raw shape of GET /api/oauth/usage. The endpoint is undocumented, so every field is
// optional and decoded with `try?`: a changed or missing field empties one value instead
// of failing the whole response.

public struct UsageResponseDTO: Decodable, Sendable {
    public var fiveHour: WindowDTO?
    public var sevenDay: WindowDTO?
    public var limits: [LimitDTO]?
    public var spend: SpendDTO?
    public var extraUsage: ExtraUsageDTO?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour", sevenDay = "seven_day", limits, spend, extraUsage = "extra_usage"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = c.lenient(WindowDTO.self, .fiveHour)
        sevenDay = c.lenient(WindowDTO.self, .sevenDay)
        limits = c.lenient([Failable<LimitDTO>].self, .limits)?.compactMap(\.value)
        spend = c.lenient(SpendDTO.self, .spend)
        extraUsage = c.lenient(ExtraUsageDTO.self, .extraUsage)
    }
}

public struct WindowDTO: Decodable, Sendable {
    public var utilization: Double?
    public var resetsAt: String?

    enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = c.lenient(Double.self, .utilization)
        resetsAt = c.lenient(String.self, .resetsAt)
    }
}

public struct LimitDTO: Decodable, Sendable {
    public var kind: String?
    public var percent: Double?
    public var resetsAt: String?
    public var modelName: String?

    enum CodingKeys: String, CodingKey { case kind, percent, resetsAt = "resets_at", scope }
    enum ScopeKeys: String, CodingKey { case model }
    enum ModelKeys: String, CodingKey { case displayName = "display_name" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(String.self, .kind)
        percent = c.lenient(Double.self, .percent)
        resetsAt = c.lenient(String.self, .resetsAt)
        let model = try? c.nestedContainer(keyedBy: ScopeKeys.self, forKey: .scope)
            .nestedContainer(keyedBy: ModelKeys.self, forKey: .model)
        modelName = model?.lenient(String.self, .displayName)
    }
}

public struct SpendDTO: Decodable, Sendable {
    public var used: MoneyDTO?
    public var limit: MoneyDTO?
    public var enabled: Bool?

    enum CodingKeys: String, CodingKey { case used, limit, enabled }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        used = c.lenient(MoneyDTO.self, .used)
        limit = c.lenient(MoneyDTO.self, .limit)
        enabled = c.lenient(Bool.self, .enabled)
    }
}

public struct MoneyDTO: Decodable, Sendable {
    public var amountMinor: Int?
    public var exponent: Int?
    public var currency: String?

    enum CodingKeys: String, CodingKey { case amountMinor = "amount_minor", exponent, currency }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amountMinor = c.lenientInt(.amountMinor)
        exponent = c.lenientInt(.exponent)
        currency = c.lenient(String.self, .currency)
    }
}

public struct ExtraUsageDTO: Decodable, Sendable {
    public var isEnabled: Bool?
    public var usedCredits: Double?
    public var monthlyLimit: Double?
    public var currency: String?
    public var decimalPlaces: Int?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled", usedCredits = "used_credits", monthlyLimit = "monthly_limit",
             currency, decimalPlaces = "decimal_places"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = c.lenient(Bool.self, .isEnabled)
        usedCredits = c.lenient(Double.self, .usedCredits)
        monthlyLimit = c.lenient(Double.self, .monthlyLimit)
        currency = c.lenient(String.self, .currency)
        decimalPlaces = c.lenientInt(.decimalPlaces)
    }
}

/// Decodes an array element without failing the whole array.
struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Accepts both `235` and `235.0`.
    func lenientInt(_ key: Key) -> Int? {
        if let int = lenient(Int.self, key) { return int }
        guard let double = lenient(Double.self, key), double.rounded() == double else { return nil }
        return Int(double)
    }
}
