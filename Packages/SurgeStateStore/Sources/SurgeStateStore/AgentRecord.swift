import Foundation
import SurgeCore

/// The state a pipeline last reported, before stall detection is applied on top.
enum AgentPhase: Equatable {
    case working
    case waitingForYou
    case compacting
    case idle(since: Date)
    case done
    case noSignal
}

/// One agent as the store keeps it: the reported phase, the token counters, and when each last
/// moved. `AgentStatus` is derived from this on every publish so stall detection has one source.
struct AgentRecord: Equatable {
    let id: String
    var provider: String
    var modelName: String
    var phase: AgentPhase
    var phaseChangedAt: Date
    var inputTokens: Int
    var outputTokens: Int
    var cacheHitTokens: Int
    var currentContextTokens: Int
    var maxContextWindow: Int
    /// The accumulated amount, kept apart by source so a total can carry the right label.
    var costBySource = SpendBySource()
    /// Estimated cost booked since this provider's last successful balance poll. A derived figure
    /// replaces it, so the same tokens are never counted twice.
    var pendingEstimateUSD = 0.0
    /// Tokens seen since that poll, used to share a balance drop between the agents that spent it.
    var tokensSinceBalancePoll = 0
    /// Tokens whose model could not be priced. While this is non-zero the cost is unavailable.
    var unpricedTokens = 0
    var lastTokenAt: Date
    var doneAt: Date?
    var parentSessionID: String?
    let isTopLevel: Bool

    /// Working tokens go quiet for the model's threshold. Waiting for you is never stalled, and
    /// an explicit state like Compacting or Idle is reported as it is.
    func status(now: Date, stallThreshold: TimeInterval) -> AgentStatus {
        switch phase {
        case .working:
            if now.timeIntervalSince(lastTokenAt) >= stallThreshold {
                return .stalled(since: lastTokenAt)
            }
            return .working
        case .waitingForYou:
            return .waitingForYou
        case .compacting:
            return .compacting
        case .idle(let since):
            return .idle(since: since)
        case .done:
            return .done
        case .noSignal:
            return .noSignal
        }
    }

    /// Applies one piece of activity or status change. Only newer events move the counters and
    /// the phase, so replaying the same events in any order reaches the same record.
    mutating func recordActivity(
        at occurredAt: Date,
        modelName: String?,
        provider: String?,
        contextTokens: Int?,
        maxContextWindow: Int?
    ) {
        if occurredAt >= lastTokenAt {
            if let contextTokens { currentContextTokens = contextTokens }
            if let maxContextWindow, maxContextWindow > 0 { self.maxContextWindow = maxContextWindow }
            if let modelName { self.modelName = modelName }
            if let provider { self.provider = provider }
            lastTokenAt = occurredAt
        }
        if occurredAt >= phaseChangedAt {
            phase = .working
            phaseChangedAt = occurredAt
            doneAt = nil
        }
    }

    func node(now: Date, stallThreshold: TimeInterval) -> AgentNode {
        AgentNode(
            id: id,
            provider: provider,
            modelName: modelName,
            status: status(now: now, stallThreshold: stallThreshold),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheHitTokens: cacheHitTokens,
            currentContextTokens: currentContextTokens,
            maxContextWindow: maxContextWindow,
            estimatedCostUSD: costBySource.totalUSD,
            costSource: costSource,
            lastTokenAt: lastTokenAt
        )
    }

    /// Nil while any turn on this agent was priced by nothing at all, so the UI says unavailable
    /// instead of showing a zero that looks like free.
    var costSource: CostSource? {
        unpricedTokens > 0 ? nil : (costBySource.source ?? .estimated)
    }
}

/// Every agent the store knows in one project folder. Top-level sessions are peers; workers are
/// sub-agents. The exported tree keeps one `WorkspaceSession` per folder, so it never shows two
/// headers for the same project.
struct WorkspaceRecord: Equatable {
    let projectPath: String
    var agents: [String: AgentRecord]

    init(projectPath: String, agents: [String: AgentRecord] = [:]) {
        self.projectPath = projectPath
        self.agents = agents
    }
}
