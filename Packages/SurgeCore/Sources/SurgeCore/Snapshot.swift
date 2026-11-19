import Foundation

/// Whether a reported amount is a spendable wallet or a cap on one key.
///
/// OpenRouter reports usage per key and, when the key has a spend limit, what is left of it. That
/// is a per-key cap, not the account wallet, so the two never read the same way.
public enum BalanceKind: String, Codable, Sendable, Equatable {
    case wallet
    case keyLimit
}

/// Why an account has no balance amount to show.
///
/// A reason is a category plus, at most, the status the provider answered with. It can never
/// carry a response body or any part of a key, which is what makes it safe to write to the
/// snapshot and to show on screen.
public struct BalanceUnavailableReason: Codable, Sendable, Equatable {
    public enum Category: String, Codable, Sendable, Equatable, CaseIterable {
        /// The provider needs an API key and none is stored.
        case notConfigured
        /// The Keychain refused the read.
        case keyUnavailable
        /// The provider answered that the key is not valid.
        case keyRejected
        /// The request never reached an answer: no network, or a timeout.
        case unreachable
        /// The provider answered with something Surge cannot read.
        case unexpectedResponse
    }

    public let category: Category
    /// The HTTP status the provider answered with, when the request reached it. Recorded for
    /// diagnosis only; the row shows the category.
    public let statusCode: Int?

    public init(_ category: Category, statusCode: Int? = nil) {
        self.category = category
        self.statusCode = statusCode
    }

    /// The short plain-English reason that appears beside an unavailable balance.
    public var text: String {
        switch category {
        case .notConfigured: "No key set"
        case .keyUnavailable: "Key not readable"
        case .keyRejected: "Key rejected"
        case .unreachable: "Could not reach provider"
        case .unexpectedResponse: "Unexpected response"
        }
    }
}

public struct AccountBalance: Identifiable, Codable, Sendable, Equatable {
    public let provider: String
    public let amountUSD: Double?
    public let lastPolledAt: Date
    public let kind: BalanceKind
    /// The provider's cumulative usage figure, when it reports one alongside the amount.
    public let usageUSD: Double?
    /// Why there is no amount, when the last poll ended without one. Nil is the design case: the
    /// provider has no balance endpoint, or answered without a figure to report.
    public let unavailableReason: BalanceUnavailableReason?
    /// A subscription account reports a window instead of a balance. When this is set the row
    /// shows burn and headroom, and it never reads as an unavailable balance.
    public let quotaWindow: QuotaWindowState?

    public init(
        provider: String,
        amountUSD: Double?,
        lastPolledAt: Date,
        kind: BalanceKind = .wallet,
        usageUSD: Double? = nil,
        unavailableReason: BalanceUnavailableReason? = nil,
        quotaWindow: QuotaWindowState? = nil
    ) {
        self.provider = provider
        self.amountUSD = amountUSD
        self.lastPolledAt = lastPolledAt
        self.kind = kind
        self.usageUSD = usageUSD
        self.unavailableReason = unavailableReason
        self.quotaWindow = quotaWindow
    }

    public var id: String { provider }

    public var isAvailable: Bool { amountUSD != nil || quotaWindow != nil }

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
        case unavailableReason
        case quotaWindow
    }

    /// A snapshot written before the balance kind existed still reads as a wallet balance.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        amountUSD = try container.decodeIfPresent(Double.self, forKey: .amountUSD)
        lastPolledAt = try container.decode(Date.self, forKey: .lastPolledAt)
        kind = try container.decodeIfPresent(BalanceKind.self, forKey: .kind) ?? .wallet
        usageUSD = try container.decodeIfPresent(Double.self, forKey: .usageUSD)
        unavailableReason = try container.decodeIfPresent(BalanceUnavailableReason.self, forKey: .unavailableReason)
        quotaWindow = try container.decodeIfPresent(QuotaWindowState.self, forKey: .quotaWindow)
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
