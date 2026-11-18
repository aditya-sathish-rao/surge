import Foundation
import SurgeCore

// MARK: - Derived state

extension SurgeStateStore {
    /// Rebuilds the exported tree, drops agents whose Done window elapsed, and publishes only
    /// when the content changed. `generatedAt` is the moment the content last changed.
    func publish(now: Date) {
        purgeExpiredDone(now: now)
        let workspaces = exportedWorkspaces(now: now)
        let balances = balanceRecords.values.sorted { $0.provider < $1.provider }
        guard workspaces != tree.workspaces || balances != tree.balances else { return }
        tree = StoreTree(
            generatedAt: now,
            workspaces: workspaces,
            balances: balances,
            balanceThresholds: balanceThresholds
        )
        for continuation in observers.values {
            continuation.yield(tree)
        }
    }

    func purgeExpiredDone(now: Date) {
        for projectPath in Array(workspaceRecords.keys) {
            guard var workspace = workspaceRecords[projectPath] else { continue }
            let expired = workspace.agents.values.compactMap { agent -> String? in
                guard agent.phase == .done, let doneAt = agent.doneAt else { return nil }
                guard now.timeIntervalSince(doneAt) > SurgeThresholds.doneDisplaySeconds else { return nil }
                return agent.id
            }
            for agentID in expired {
                workspace.agents[agentID] = nil
            }
            workspaceRecords[projectPath] = workspace.agents.isEmpty ? nil : workspace
        }
    }

    private func exportedWorkspaces(now: Date) -> [WorkspaceSession] {
        workspaceRecords.keys.sorted().compactMap { projectPath in
            guard let workspace = workspaceRecords[projectPath] else { return nil }
            return exportedSession(from: workspace, now: now)
        }
        .sorted(by: Self.workspaceOrder)
    }

    /// One workspace per folder, with peers and sub-agents in `workers`.
    private func exportedSession(from workspace: WorkspaceRecord, now: Date) -> WorkspaceSession? {
        let agents = workspace.agents
        guard let orchestrator = orchestrator(in: agents) else { return nil }
        let others = agents.values.filter { $0.id != orchestrator.id }
        let ordered = agentsInOrder(Array(others), orchestratedBy: orchestrator, now: now)
        return WorkspaceSession(
            id: workspaceID(for: workspace.projectPath),
            projectPath: workspace.projectPath,
            orchestrator: node(for: orchestrator, now: now),
            workers: ordered.map { node(for: $0, now: now) }
        )
    }

    /// A worker nests under the top-level session that named it as its parent. When no session
    /// is named, or more than one is, the most recently active top-level session heads the
    /// workspace instead of picking arbitrarily between peers. A worker is promoted only when
    /// no top-level session is left. Ties go to the lower session ID, so nothing here depends
    /// on arrival order.
    private func orchestrator(in agents: [String: AgentRecord]) -> AgentRecord? {
        let topLevel = agents.values.filter(\.isTopLevel)
        guard topLevel.isEmpty == false else {
            return agents.values.max(by: ranksBelow)
        }
        let parentIDs = Set(agents.values.compactMap(\.parentSessionID))
        let named = topLevel.filter { parentIDs.contains($0.id) }
        if named.count == 1, let parent = named.first { return parent }
        return topLevel.max(by: ranksBelow)
    }

    private func ranksBelow(_ lhs: AgentRecord, _ rhs: AgentRecord) -> Bool {
        if lhs.lastTokenAt != rhs.lastTokenAt { return lhs.lastTokenAt < rhs.lastTokenAt }
        return lhs.id > rhs.id
    }

    /// PRD 6.2 order: the orchestrator's sub-agents follow it, then each remaining peer with its
    /// own sub-agents, then anything whose parent is gone. Agents needing the user sort first
    /// inside each group.
    private func agentsInOrder(
        _ agents: [AgentRecord],
        orchestratedBy orchestrator: AgentRecord,
        now: Date
    ) -> [AgentRecord] {
        var included: Set<String> = [orchestrator.id]
        var ordered: [AgentRecord] = []

        for child in sortedByAttention(children(of: orchestrator.id, in: agents), now: now)
        where included.insert(child.id).inserted {
            ordered.append(child)
        }

        let peers = agents.filter { $0.isTopLevel }
        for peer in peers.sorted(by: { peerOrder($0, $1, now: now) }) where included.insert(peer.id).inserted {
            ordered.append(peer)
            for child in sortedByAttention(children(of: peer.id, in: agents), now: now)
            where included.insert(child.id).inserted {
                ordered.append(child)
            }
        }

        for leftover in sortedByAttention(agents.filter { included.contains($0.id) == false }, now: now)
        where included.insert(leftover.id).inserted {
            ordered.append(leftover)
        }
        return ordered
    }

    private func children(of parentID: String, in agents: [AgentRecord]) -> [AgentRecord] {
        agents.filter { $0.parentSessionID == parentID }
    }

    private func sortedByAttention(_ agents: [AgentRecord], now: Date) -> [AgentRecord] {
        agents.sorted { lhs, rhs in
            let lhsNeedsYou = needsYou(lhs, now: now)
            let rhsNeedsYou = needsYou(rhs, now: now)
            if lhsNeedsYou != rhsNeedsYou { return lhsNeedsYou }
            return lhs.id < rhs.id
        }
    }

    private func peerOrder(_ lhs: AgentRecord, _ rhs: AgentRecord, now: Date) -> Bool {
        let lhsNeedsYou = needsYou(lhs, now: now)
        let rhsNeedsYou = needsYou(rhs, now: now)
        if lhsNeedsYou != rhsNeedsYou { return lhsNeedsYou }
        return ranksBelow(rhs, lhs)
    }

    private func needsYou(_ agent: AgentRecord, now: Date) -> Bool {
        agent.status(now: now, stallThreshold: stallThreshold(for: agent)).needsYou
    }

    private func stallThreshold(for agent: AgentRecord) -> TimeInterval {
        pricing.stallThresholdSeconds(forModel: agent.modelName)
    }

    private func node(for agent: AgentRecord, now: Date) -> AgentNode {
        agent.node(now: now, stallThreshold: stallThreshold(for: agent))
    }

    /// Workspaces needing attention first, then by spend, then by path so ties never depend on
    /// dictionary order.
    private static func workspaceOrder(_ lhs: WorkspaceSession, _ rhs: WorkspaceSession) -> Bool {
        if lhs.needsYou != rhs.needsYou { return lhs.needsYou }
        if lhs.totalTreeCostUSD != rhs.totalTreeCostUSD {
            return lhs.totalTreeCostUSD > rhs.totalTreeCostUSD
        }
        return lhs.projectPath < rhs.projectPath
    }
}
