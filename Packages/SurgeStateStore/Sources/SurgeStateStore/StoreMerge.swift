import Foundation
import SurgeCore

/// Where an agent currently sits in the tree.
struct AgentLocation {
    let projectPath: String
    let agent: AgentRecord
}

extension SurgeStateStore {
    // MARK: - Pipeline events

    func merge(session descriptor: SessionDescriptor) {
        let existing = agentLocation(forID: descriptor.id)
        var agent =
            existing?.agent
            ?? AgentRecord(
                id: descriptor.id,
                provider: descriptor.provider,
                modelName: descriptor.modelName,
                phase: .working,
                phaseChangedAt: descriptor.occurredAt,
                inputTokens: 0,
                outputTokens: 0,
                cacheHitTokens: 0,
                currentContextTokens: 0,
                maxContextWindow: descriptor.maxContextWindow,
                lastTokenAt: descriptor.occurredAt,
                doneAt: nil,
                parentSessionID: descriptor.parentSessionID,
                isTopLevel: descriptor.parentSessionID == nil,
                harness: descriptor.harness
            )
        if let harness = descriptor.harness {
            agent.harness = harness
        }
        // A sub-agent transcript names its parent, so it is never a peer of the session that
        // spawned it even when it was tailed first.
        if let parent = descriptor.parentSessionID, parent != agent.id {
            agent.parentSessionID = parent
            agent.isTopLevel = false
        }
        let contextWindow =
            descriptor.maxContextWindow > 0
            ? descriptor.maxContextWindow
            : priceBook.contextWindow(forModel: descriptor.modelName)
        agent.recordActivity(
            at: descriptor.occurredAt,
            modelName: descriptor.modelName,
            provider: descriptor.provider,
            contextTokens: nil,
            maxContextWindow: contextWindow
        )
        fillContextWindowIfNeeded(&agent)
        if let existing, existing.projectPath != descriptor.projectPath {
            removeAgent(id: descriptor.id)
        }
        replace(agent, at: descriptor.projectPath)
        resolveAttributionIfNeeded(forAgentID: descriptor.id)
    }

    func merge(turn: TurnAppended) {
        guard let rootLocation = treeRoot(forAgentID: turn.sessionID),
            agentLocation(forID: turn.sessionID) != nil
        else { return }
        // One record id is one turn, counted once for the whole session tree.
        if let eventID = turn.eventID {
            var root = rootLocation.agent
            guard root.seenEventIDs.insert(eventID).inserted else { return }
            replace(root, at: rootLocation.projectPath)
        }
        resolveAttributionIfNeeded(forAgentID: turn.sessionID)
        guard let location = agentLocation(forID: turn.sessionID) else { return }
        var agent = location.agent
        agent.inputTokens += turn.inputTokens
        agent.outputTokens += turn.outputTokens
        agent.cacheHitTokens += turn.cacheHitTokens
        book(
            cost: &agent,
            modelName: turn.modelName,
            inputTokens: turn.inputTokens,
            outputTokens: turn.outputTokens,
            cacheHitTokens: turn.cacheHitTokens,
            harnessReportedCumulativeUSD: turn.harnessReportedCostUSD
        )
        agent.recordActivity(
            at: turn.occurredAt,
            modelName: turn.modelName,
            provider: nil,
            contextTokens: turn.currentContextTokens,
            maxContextWindow: priceBook.contextWindow(forModel: turn.modelName)
        )
        replace(agent, at: location.projectPath)
    }

    func merge(sessionEnded sessionID: String, at occurredAt: Date) {
        guard let location = agentLocation(forID: sessionID) else { return }
        var agent = location.agent
        guard occurredAt >= agent.phaseChangedAt else { return }
        agent.phase = .done
        agent.phaseChangedAt = occurredAt
        agent.doneAt = occurredAt
        replace(agent, at: location.projectPath)
    }

    func merge(worker descriptor: WorkerDescriptor) {
        let existing = agentLocation(forID: descriptor.id)
        var agent =
            existing?.agent
            ?? AgentRecord(
                id: descriptor.id,
                provider: descriptor.provider,
                modelName: descriptor.modelName,
                phase: .working,
                phaseChangedAt: descriptor.occurredAt,
                inputTokens: 0,
                outputTokens: 0,
                cacheHitTokens: 0,
                currentContextTokens: 0,
                maxContextWindow: 0,
                lastTokenAt: descriptor.occurredAt,
                doneAt: nil,
                parentSessionID: descriptor.parentSessionID,
                isTopLevel: false,
                // A proxy worker is not a harness by name: it is whatever program pointed its base
                // URL at Surge. Saying so keeps inference out of the record.
                harness: descriptor.harness
                    ?? HarnessIdentity(kind: .generic, sessionID: descriptor.id, transport: .proxy)
            )
        if descriptor.occurredAt >= agent.phaseChangedAt {
            agent.parentSessionID = descriptor.parentSessionID
        }
        agent.recordActivity(
            at: descriptor.occurredAt,
            modelName: descriptor.modelName,
            provider: descriptor.provider,
            contextTokens: nil,
            maxContextWindow: priceBook.contextWindow(forModel: descriptor.modelName)
        )
        fillContextWindowIfNeeded(&agent)
        if let existing, existing.projectPath != descriptor.projectPath {
            removeAgent(id: descriptor.id)
        }
        replace(agent, at: descriptor.projectPath)
        resolveAttributionIfNeeded(forAgentID: descriptor.id)
    }

    func merge(usage: ProxyUsage) {
        guard let location = agentLocation(forID: usage.workerID) else { return }
        resolveAttributionIfNeeded(forAgentID: usage.workerID)
        guard let refreshed = agentLocation(forID: usage.workerID) else { return }
        var agent = refreshed.agent
        agent.inputTokens += usage.inputTokens
        agent.outputTokens += usage.outputTokens
        agent.cacheHitTokens += usage.cacheHitTokens
        book(
            cost: &agent,
            modelName: usage.modelName,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheHitTokens: usage.cacheHitTokens,
            providerReportedUSD: usage.reportedCostUSD
        )
        agent.recordActivity(
            at: usage.occurredAt,
            modelName: usage.modelName,
            provider: usage.provider,
            contextTokens: usage.currentContextTokens,
            maxContextWindow: priceBook.contextWindow(forModel: usage.modelName)
        )
        replace(agent, at: location.projectPath)
    }

    func merge(status: AgentStatus, for agentID: String, at occurredAt: Date) {
        guard let location = agentLocation(forID: agentID) else { return }
        var agent = location.agent
        guard occurredAt >= agent.phaseChangedAt else { return }
        switch status {
        case .working:
            agent.phase = .working
            agent.doneAt = nil
        case .waitingForYou:
            agent.phase = .waitingForYou
        case .compacting:
            agent.phase = .compacting
        case .idle(let since):
            agent.phase = .idle(since: since)
        case .done:
            agent.phase = .done
            agent.doneAt = occurredAt
        case .noSignal:
            agent.phase = .noSignal
        case .stalled:
            return
        }
        agent.phaseChangedAt = occurredAt
        replace(agent, at: location.projectPath)
    }

    // MARK: - Records

    private func fillContextWindowIfNeeded(_ agent: inout AgentRecord) {
        if agent.maxContextWindow == 0 {
            agent.maxContextWindow = priceBook.contextWindow(forModel: agent.modelName) ?? 0
        }
    }

    func agentLocation(forID id: String) -> AgentLocation? {
        for projectPath in workspaceRecords.keys.sorted() {
            if let agent = workspaceRecords[projectPath]?.agents[id] {
                return AgentLocation(projectPath: projectPath, agent: agent)
            }
        }
        return nil
    }

    func replace(_ agent: AgentRecord, at projectPath: String) {
        var workspace = workspaceRecords[projectPath] ?? WorkspaceRecord(projectPath: projectPath)
        workspace.agents[agent.id] = agent
        workspaceRecords[projectPath] = workspace
    }

    func removeAgent(id: String) {
        for projectPath in workspaceRecords.keys.sorted() {
            guard
                var workspace = workspaceRecords[projectPath],
                workspace.agents.removeValue(forKey: id) != nil
            else { continue }
            workspaceRecords[projectPath] = workspace.agents.isEmpty ? nil : workspace
        }
    }

    func allAgentLocations() -> [AgentLocation] {
        var locations: [AgentLocation] = []
        for projectPath in workspaceRecords.keys.sorted() {
            guard let workspace = workspaceRecords[projectPath] else { continue }
            for id in workspace.agents.keys.sorted() {
                guard let agent = workspace.agents[id] else { continue }
                locations.append(AgentLocation(projectPath: projectPath, agent: agent))
            }
        }
        return locations
    }
}
