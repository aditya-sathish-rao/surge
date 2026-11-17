import Foundation

public struct AccountBalance: Identifiable, Codable, Sendable, Equatable {
    public let provider: String
    public let amountUSD: Double?
    public let lastPolledAt: Date

    public init(provider: String, amountUSD: Double?, lastPolledAt: Date) {
        self.provider = provider
        self.amountUSD = amountUSD
        self.lastPolledAt = lastPolledAt
    }

    public var id: String { provider }

    public var isAvailable: Bool { amountUSD != nil }

    public var providerKind: Provider { Provider(providerID: provider) ?? .other }

    public var level: BalanceLevel? {
        amountUSD.map(SurgeThresholds.balanceLevel(forUSD:))
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
