import Foundation

/// How a dollar figure was obtained, strongest first.
///
/// The label always travels with the number: a figure is reported by the provider that billed it,
/// reported by the harness that ran the agent, derived from a movement in a reported balance, read
/// off a subscription's quota window, or computed locally from a price table. They are never
/// blended into one silent total.
public enum CostSource: String, Codable, Sendable, Equatable, CaseIterable {
    /// The provider that billed the call reported its exact cost.
    case providerReported = "provider-reported"
    /// The harness reported its own total. Claude Code computes this at Anthropic list prices, so
    /// it is not the bill when the session is routed through a different provider.
    case harnessReported = "harness-reported"
    /// Derived from a movement in the provider's reported balance, not a per-call figure.
    case balanceDerived = "balance-derived"
    /// Read against a subscription's quota window, which is a notional ceiling rather than a bill.
    case quotaWindow = "quota-window"
    /// Computed locally from a price table, so it is only as good as that table.
    case estimated
    /// Nothing could report an amount. The balance-derived and quota-window rules still apply
    /// before a figure is ever labelled this way.
    case unavailable

    public var label: String {
        switch self {
        case .providerReported: "Provider reported"
        case .harnessReported: "Harness reported"
        case .balanceDerived: "Balance derived"
        case .quotaWindow: "Quota window"
        case .estimated: "Estimated"
        case .unavailable: "Unavailable"
        }
    }

    /// The short word that sits beside the amount wherever space is tight.
    public var suffix: String {
        switch self {
        case .providerReported: "provider"
        case .harnessReported: "harness"
        case .balanceDerived: "derived"
        case .quotaWindow: "quota"
        case .estimated: "est."
        case .unavailable: "unavailable"
        }
    }

    /// Strength order, strongest first. A quota window sits below a balance movement because the
    /// window's ceiling is the user's own number, and above a generic estimate because it is
    /// measured against something real.
    public var rank: Int {
        switch self {
        case .providerReported: 0
        case .harnessReported: 1
        case .balanceDerived: 2
        case .quotaWindow: 3
        case .estimated: 4
        case .unavailable: 5
        }
    }

    /// A total is only as strong as its weakest part.
    public static func weakest(_ sources: [CostSource]) -> CostSource? {
        sources.max { $0.rank < $1.rank }
    }

    private enum LegacyValue {
        static let actual = "actual"
        static let derived = "derived"
    }

    /// A snapshot written before this vocabulary existed names the provider figure `actual` and
    /// the balance figure `derived`. Both still read as the case they became.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case LegacyValue.actual: self = .providerReported
        case LegacyValue.derived: self = .balanceDerived
        default:
            guard let source = CostSource(rawValue: raw) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown cost source \(raw)"
                    )
                )
            }
            self = source
        }
    }
}

/// One dollar amount together with where it came from.
public struct SpendFigure: Codable, Sendable, Equatable {
    public let amountUSD: Double
    public let source: CostSource

    public init(amountUSD: Double, source: CostSource) {
        self.amountUSD = amountUSD
        self.source = source
    }

    public var amountText: String {
        SurgeFormatting.cost(amountUSD)
    }

    /// The number and its label as one string. Never show one without the other.
    public var displayText: String {
        "\(amountText) \(source.suffix)"
    }

    public var accessibilityText: String {
        "\(amountText), \(source.label.lowercased())"
    }
}

/// Spend kept apart by how it was obtained, so a total can carry the right label.
public struct SpendBySource: Codable, Sendable, Equatable {
    public private(set) var providerReportedUSD: Double
    public private(set) var harnessReportedUSD: Double
    public private(set) var balanceDerivedUSD: Double
    public private(set) var quotaWindowUSD: Double
    public private(set) var estimatedUSD: Double

    public init(
        providerReportedUSD: Double = 0,
        harnessReportedUSD: Double = 0,
        balanceDerivedUSD: Double = 0,
        quotaWindowUSD: Double = 0,
        estimatedUSD: Double = 0
    ) {
        self.providerReportedUSD = providerReportedUSD
        self.harnessReportedUSD = harnessReportedUSD
        self.balanceDerivedUSD = balanceDerivedUSD
        self.quotaWindowUSD = quotaWindowUSD
        self.estimatedUSD = estimatedUSD
    }

    public var totalUSD: Double {
        providerReportedUSD + harnessReportedUSD + balanceDerivedUSD + quotaWindowUSD + estimatedUSD
    }

    public mutating func add(_ amount: Double, source: CostSource) {
        guard amount > 0 else { return }
        switch source {
        case .providerReported: providerReportedUSD += amount
        case .harnessReported: harnessReportedUSD += amount
        case .balanceDerived: balanceDerivedUSD += amount
        case .quotaWindow: quotaWindowUSD += amount
        case .estimated: estimatedUSD += amount
        case .unavailable: return
        }
    }

    /// Takes back local estimates that a stronger figure has replaced.
    public mutating func removeEstimate(_ amount: Double) {
        guard amount > 0 else { return }
        estimatedUSD = max(estimatedUSD - amount, 0)
    }

    /// Takes back one window's booked spend, bucket by bucket, when a derived figure replaces it.
    public mutating func remove(_ other: SpendBySource) {
        providerReportedUSD = max(providerReportedUSD - other.providerReportedUSD, 0)
        harnessReportedUSD = max(harnessReportedUSD - other.harnessReportedUSD, 0)
        balanceDerivedUSD = max(balanceDerivedUSD - other.balanceDerivedUSD, 0)
        quotaWindowUSD = max(quotaWindowUSD - other.quotaWindowUSD, 0)
        estimatedUSD = max(estimatedUSD - other.estimatedUSD, 0)
    }

    /// The weakest source contributing to the total, or nil when nothing has been booked.
    public var source: CostSource? {
        var sources: [CostSource] = []
        if providerReportedUSD > 0 { sources.append(.providerReported) }
        if harnessReportedUSD > 0 { sources.append(.harnessReported) }
        if balanceDerivedUSD > 0 { sources.append(.balanceDerived) }
        if quotaWindowUSD > 0 { sources.append(.quotaWindow) }
        if estimatedUSD > 0 { sources.append(.estimated) }
        return CostSource.weakest(sources)
    }

    /// The total with its label. A zero total is an estimate of nothing, never a reported figure.
    public func figure(defaultingTo fallback: CostSource = .estimated) -> SpendFigure {
        SpendFigure(amountUSD: totalUSD, source: source ?? fallback)
    }
}

/// What one balance poll says moved on an account.
public struct BalanceMovement: Sendable, Equatable {
    public let provider: Provider
    /// The amount the balance fell by. Zero for a top-up, because a top-up is not negative spend.
    public let dropUSD: Double
    public let wasTopUp: Bool

    public init(provider: Provider, dropUSD: Double, wasTopUp: Bool) {
        self.provider = provider
        self.dropUSD = dropUSD
        self.wasTopUp = wasTopUp
    }

    public var hasSpend: Bool {
        dropUSD > 0 && !wasTopUp
    }
}

/// Turns balance movements into spend without ever inventing a negative number.
public enum SpendAttribution {
    private static let tolerance = 0.000_001

    /// A drop in the reported balance is spend. An increase is a top-up, not negative spend.
    /// A first poll has nothing to compare against, so it reports no movement.
    public static func movement(
        provider: Provider,
        previousUSD: Double?,
        currentUSD: Double?
    ) -> BalanceMovement? {
        guard let previousUSD, let currentUSD else { return nil }
        let drop = previousUSD - currentUSD
        if drop > tolerance {
            return BalanceMovement(provider: provider, dropUSD: drop, wasTopUp: false)
        }
        if drop < -tolerance {
            return BalanceMovement(provider: provider, dropUSD: 0, wasTopUp: true)
        }
        return nil
    }

    /// Splits a drop across the agents seen in the window in proportion to their tokens.
    ///
    /// Ids are sorted so the split is deterministic, and the last share takes the rounding
    /// remainder so the parts add back up to the whole drop.
    public static func shares(dropUSD: Double, tokensByAgent: [String: Int]) -> [String: Double] {
        let positive = tokensByAgent.filter { $0.value > 0 }
        let totalTokens = positive.values.reduce(0, +)
        guard dropUSD > 0, totalTokens > 0 else { return [:] }
        let ids = positive.keys.sorted()
        var shares: [String: Double] = [:]
        var remaining = dropUSD
        for id in ids.dropLast() {
            let share = dropUSD * Double(positive[id] ?? 0) / Double(totalTokens)
            shares[id] = share
            remaining -= share
        }
        if let last = ids.last {
            shares[last] = remaining
        }
        return shares
    }
}

/// What one turn's numbers can be booked from: the provider's bill, the harness's own total, or
/// a local estimate. A balance-derived figure is booked later, when the account's balance moves.
public struct TurnFigures: Sendable, Equatable {
    public let providerReportedUSD: Double?
    public let harnessReportedUSD: Double?
    public let estimateUSD: Double?

    public init(
        providerReportedUSD: Double? = nil,
        harnessReportedUSD: Double? = nil,
        estimateUSD: Double? = nil
    ) {
        self.providerReportedUSD = providerReportedUSD
        self.harnessReportedUSD = harnessReportedUSD
        self.estimateUSD = estimateUSD
    }
}
