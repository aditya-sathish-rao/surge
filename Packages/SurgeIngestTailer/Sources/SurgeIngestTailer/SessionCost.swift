import Foundation

/// Where the costs recorded for a session came from.
public enum CostProvenance: String, Codable, Sendable, Equatable {
    /// The provider billed this amount and the transcript recorded it.
    case providerReported
    /// The harness reported its own running total for the session.
    case harnessReported
    /// The tailer priced the tokens from its own pricing table.
    case locallyEstimated
    /// Turns from more than one provenance. Their sums stay separate.
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
    /// The harness's own figure for the session: a sum of its per-turn amounts when it writes one,
    /// or its running total when that is all it writes.
    public let harnessReportedUSD: Double?
    /// Sum of the turns the tailer priced from its pricing table. Nil when there were none.
    public let locallyEstimatedUSD: Double?
    /// Turns for which neither the source nor the pricing table supplied a cost.
    public let unavailableTurnCount: Int

    public init(
        sessionID: String,
        provider: String,
        providerReportedUSD: Double?,
        locallyEstimatedUSD: Double?,
        unavailableTurnCount: Int,
        harnessReportedUSD: Double? = nil
    ) {
        self.sessionID = sessionID
        self.provider = provider
        self.providerReportedUSD = providerReportedUSD
        self.harnessReportedUSD = harnessReportedUSD
        self.locallyEstimatedUSD = locallyEstimatedUSD
        self.unavailableTurnCount = unavailableTurnCount
    }

    public var provenance: CostProvenance {
        let sources = [
            providerReportedUSD != nil,
            harnessReportedUSD != nil,
            locallyEstimatedUSD != nil,
        ].filter { $0 }.count
        switch sources {
        case 0: return .unavailable
        case 1:
            if providerReportedUSD != nil { return .providerReported }
            if harnessReportedUSD != nil { return .harnessReported }
            return .locallyEstimated
        default: return .mixed
        }
    }
}

/// Adds up the turns of one session, keeping billed, harness-reported and estimated amounts apart.
struct SessionCostAccumulator: Equatable {
    private(set) var providerReportedUSD: Double?
    private(set) var harnessReportedUSD: Double?
    private(set) var locallyEstimatedUSD: Double?
    private(set) var unavailableTurnCount = 0

    mutating func add(_ cost: TurnCost) {
        switch cost {
        case .providerReported(let amount):
            providerReportedUSD = (providerReportedUSD ?? 0) + amount
        case .harnessReported(let amount):
            harnessReportedUSD = (harnessReportedUSD ?? 0) + amount
        case .locallyEstimated(let amount):
            locallyEstimatedUSD = (locallyEstimatedUSD ?? 0) + amount
        case .unavailable:
            unavailableTurnCount += 1
        }
    }

    /// The harness reports a running total rather than a per-turn amount, so the latest one wins.
    mutating func recordHarnessTotal(_ total: Double?) {
        guard let total else { return }
        harnessReportedUSD = total
    }

    func summary(sessionID: String, provider: String) -> SessionCost {
        SessionCost(
            sessionID: sessionID,
            provider: provider,
            providerReportedUSD: providerReportedUSD,
            locallyEstimatedUSD: locallyEstimatedUSD,
            unavailableTurnCount: unavailableTurnCount,
            harnessReportedUSD: harnessReportedUSD
        )
    }
}
