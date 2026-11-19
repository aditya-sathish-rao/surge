import Foundation

/// Whether a reported amount is a spendable wallet or a cap on one key.
///
/// OpenRouter reports usage per key and, when the key has a spend limit, what is left of it. That
/// is a per-key cap, not the account wallet, so the two never read the same way.
public enum BalanceKind: String, Codable, Sendable, Equatable {
    case wallet
    case keyLimit
}

public struct AccountBalance: Identifiable, Codable, Sendable, Equatable {
    public let provider: String
    public let amountUSD: Double?
    public let lastPolledAt: Date
    public let kind: BalanceKind
    /// The provider's cumulative usage figure, when it reports one alongside the amount.
    public let usageUSD: Double?

    public init(
        provider: String,
        amountUSD: Double?,
        lastPolledAt: Date,
        kind: BalanceKind = .wallet,
        usageUSD: Double? = nil
    ) {
        self.provider = provider
        self.amountUSD = amountUSD
        self.lastPolledAt = lastPolledAt
        self.kind = kind
        self.usageUSD = usageUSD
    }

    public var id: String { provider }

    public var isAvailable: Bool { amountUSD != nil }

    public var providerKind: Provider { Provider(providerID: provider) ?? .other }

    public var level: BalanceLevel? {
        amountUSD.map(SurgeThresholds.balanceLevel(forUSD:))
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case amountUSD
        case lastPolledAt
        case kind
        case usageUSD
    }

    /// A snapshot written before the balance kind existed still reads as a wallet balance.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        amountUSD = try container.decodeIfPresent(Double.self, forKey: .amountUSD)
        lastPolledAt = try container.decode(Date.self, forKey: .lastPolledAt)
        kind = try container.decodeIfPresent(BalanceKind.self, forKey: .kind) ?? .wallet
        usageUSD = try container.decodeIfPresent(Double.self, forKey: .usageUSD)
    }
}

public struct DailySpendPoint: Identifiable, Codable, Sendable, Equatable {
    public let date: Date
    public let spendByProvider: [String: Double]

    public init(date: Date, spendByProvider: [String: Double] = [:]) {
        self.date = date
        self.spendByProvider = spendByProvider
    }

    public var id: Date { date }

    public var totalUSD: Double {
        spendByProvider.values.reduce(0, +)
    }

    public func spend(for provider: Provider) -> Double {
        spendByProvider[provider.rawValue] ?? 0
    }
}

public struct SurgeSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let workspaces: [WorkspaceSession]
    public let balances: [AccountBalance]
    public let dailySpend: [DailySpendPoint]

    public init(
        generatedAt: Date,
        workspaces: [WorkspaceSession],
        balances: [AccountBalance],
        dailySpend: [DailySpendPoint],
        schemaVersion: Int = SurgeSnapshot.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.workspaces = workspaces
        self.balances = balances
        self.dailySpend = dailySpend
    }

    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(generatedAt) > SurgeThresholds.snapshotStaleSeconds
    }
}
