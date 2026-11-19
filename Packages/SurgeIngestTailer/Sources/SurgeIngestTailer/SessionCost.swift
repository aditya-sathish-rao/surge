import Foundation

/// Where the costs recorded for a session came from.
public enum CostProvenance: String, Codable, Sendable, Equatable {
    /// The provider billed this amount and the transcript recorded it.
    case providerReported
    /// The tailer priced the tokens from its own pricing table.
    case locallyEstimated
    /// Some turns were billed and some were estimated. The two sums stay separate.
    case mixed
    /// No turn in the session carried a cost the tailer could trust.
    case unavailable
}

/// The cost recorded for one session, kept split by provenance so the two are never added together.
///
/// The frozen `TurnAppended` event has no cost field, so costs are reported through this type
/// instead of through the event stream.
public struct SessionCost: Codable, Sendable, Equatable {
    public let sessionID: String
    public let provider: String
    /// Sum of the turns whose cost the provider itself reported. Nil when there were none.
    public let providerReportedUSD: Double?
    /// Sum of the turns the tailer priced from its pricing table. Nil when there were none.
    public let locallyEstimatedUSD: Double?
    /// Turns for which neither the source nor the pricing table supplied a cost.
    public let unavailableTurnCount: Int

    public init(
        sessionID: String,
        provider: String,
        providerReportedUSD: Double?,
        locallyEstimatedUSD: Double?,
        unavailableTurnCount: Int
    ) {
        self.sessionID = sessionID
        self.provider = provider
        self.providerReportedUSD = providerReportedUSD
        self.locallyEstimatedUSD = locallyEstimatedUSD
        self.unavailableTurnCount = unavailableTurnCount
    }

    public var provenance: CostProvenance {
        switch (providerReportedUSD != nil, locallyEstimatedUSD != nil) {
        case (true, true): .mixed
        case (true, false): .providerReported
        case (false, true): .locallyEstimated
        case (false, false): .unavailable
        }
    }
}

/// Adds up the turns of one session, keeping billed and estimated amounts apart.
struct SessionCostAccumulator: Equatable {
    private(set) var providerReportedUSD: Double?
    private(set) var locallyEstimatedUSD: Double?
    private(set) var unavailableTurnCount = 0

    mutating func add(_ cost: TurnCost) {
        switch cost {
        case .providerReported(let amount):
            providerReportedUSD = (providerReportedUSD ?? 0) + amount
        case .locallyEstimated(let amount):
            locallyEstimatedUSD = (locallyEstimatedUSD ?? 0) + amount
        case .unavailable:
            unavailableTurnCount += 1
        }
    }

    func summary(sessionID: String, provider: String) -> SessionCost {
        SessionCost(
            sessionID: sessionID,
            provider: provider,
            providerReportedUSD: providerReportedUSD,
            locallyEstimatedUSD: locallyEstimatedUSD,
            unavailableTurnCount: unavailableTurnCount
        )
    }
}
