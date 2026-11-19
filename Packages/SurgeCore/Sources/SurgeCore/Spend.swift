import Foundation

/// How a dollar figure was obtained, strongest first.
///
/// The label always travels with the number: a figure is either reported by the provider, derived
/// from a balance movement, or computed locally from a price table. The three are never blended
/// into one silent total.
public enum CostSource: String, Codable, Sendable, Equatable, CaseIterable {
    /// The provider reported the exact cost of the call or account usage.
    case actual
    /// Derived from a movement in the provider's reported balance, not a per-call figure.
    case derived
    /// Computed locally from a price table, so it is only as good as that table.
    case estimated

    public var label: String {
        switch self {
        case .actual: "Actual"
        case .derived: "Derived"
        case .estimated: "Estimated"
        }
    }

    /// The short word that sits beside the amount wherever space is tight.
    public var suffix: String {
        switch self {
        case .actual: "actual"
        case .derived: "derived"
        case .estimated: "est."
        }
    }

    /// Strength order, strongest first.
    public var rank: Int {
        switch self {
        case .actual: 0
        case .derived: 1
        case .estimated: 2
        }
    }

    /// A total is only as strong as its weakest part.
    public static func weakest(_ sources: [CostSource]) -> CostSource? {
        sources.max { $0.rank < $1.rank }
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
    public private(set) var actualUSD: Double
    public private(set) var derivedUSD: Double
    public private(set) var estimatedUSD: Double

    public init(actualUSD: Double = 0, derivedUSD: Double = 0, estimatedUSD: Double = 0) {
        self.actualUSD = actualUSD
        self.derivedUSD = derivedUSD
        self.estimatedUSD = estimatedUSD
    }

    public var totalUSD: Double {
        actualUSD + derivedUSD + estimatedUSD
    }

    public mutating func add(_ amount: Double, source: CostSource) {
        guard amount > 0 else { return }
        switch source {
        case .actual: actualUSD += amount
        case .derived: derivedUSD += amount
        case .estimated: estimatedUSD += amount
        }
    }

    /// Takes back local estimates that a stronger figure has replaced.
    public mutating func removeEstimate(_ amount: Double) {
        guard amount > 0 else { return }
        estimatedUSD = max(estimatedUSD - amount, 0)
    }

    /// The weakest source contributing to the total, or nil when nothing has been booked.
    public var source: CostSource? {
        var sources: [CostSource] = []
        if actualUSD > 0 { sources.append(.actual) }
        if derivedUSD > 0 { sources.append(.derived) }
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
