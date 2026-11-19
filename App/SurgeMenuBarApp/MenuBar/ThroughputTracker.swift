import Foundation
import SurgeCore
import SurgeUI

/// Turns changed token counters into the tok/s a row shows, plus the 30-minute series the Usage
/// tab draws. Rates decay to zero when output stops, so a quiet agent never reads as busy.
struct ThroughputTracker: Equatable {
    static let sampleWindow: TimeInterval = 1800
    static let quietAfter: TimeInterval = 3
    static let sampleInterval: TimeInterval = 1
    /// A delta inside this window is folded into the next one, so two events that arrive together
    /// never divide a whole turn by a few milliseconds.
    static let minimumRateInterval: TimeInterval = 0.5

    private var outputTokens: [String: Int] = [:]
    private var lastSeenAt: [String: Date] = [:]
    private var rates: [String: Double] = [:]
    private(set) var samples: [ThroughputSample] = []

    var totalTokensPerSecond: Double {
        rates.values.reduce(0, +)
    }

    func rate(for agentID: String) -> Double? {
        guard let rate = rates[agentID], rate > 0 else { return nil }
        return rate
    }

    mutating func record(workspaces: [WorkspaceSession], at now: Date) {
        let agents = Self.agents(in: workspaces)
        var active: Set<String> = []
        for agent in agents {
            active.insert(agent.id)
            let previousTokens = outputTokens[agent.id]
            let previousAt = lastSeenAt[agent.id]
            let produced = max(agent.outputTokens - (previousTokens ?? agent.outputTokens), 0)
            let elapsed = previousAt.map { now.timeIntervalSince($0) } ?? 0
            if agent.status == .working, produced > 0, elapsed >= Self.minimumRateInterval {
                rates[agent.id] = Double(produced) / elapsed
                outputTokens[agent.id] = agent.outputTokens
                lastSeenAt[agent.id] = now
            } else if produced == 0, let previousAt, now.timeIntervalSince(previousAt) > Self.quietAfter {
                rates[agent.id] = 0
                outputTokens[agent.id] = agent.outputTokens
                lastSeenAt[agent.id] = now
            } else if previousTokens == nil {
                outputTokens[agent.id] = agent.outputTokens
                lastSeenAt[agent.id] = now
            }
        }
        for id in rates.keys where !active.contains(id) {
            rates[id] = 0
        }
        appendSample(at: now)
    }

    private mutating func appendSample(at now: Date) {
        if let last = samples.last, now.timeIntervalSince(last.date) < Self.sampleInterval {
            samples[samples.count - 1] = ThroughputSample(date: last.date, tokensPerSecond: totalTokensPerSecond)
        } else {
            samples.append(ThroughputSample(date: now, tokensPerSecond: totalTokensPerSecond))
        }
        let cutoff = now.addingTimeInterval(-Self.sampleWindow)
        if let firstFresh = samples.firstIndex(where: { $0.date >= cutoff }), firstFresh > 0 {
            samples.removeFirst(firstFresh)
        }
    }

    /// Orchestrators and workers in the order the store supplies them.
    private static func agents(in workspaces: [WorkspaceSession]) -> [AgentNode] {
        workspaces.flatMap { workspace in
            [workspace.orchestrator] + workspace.workers
        }
    }
}
