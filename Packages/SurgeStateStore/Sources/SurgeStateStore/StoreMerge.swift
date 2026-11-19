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
                parentSessionID: nil,
                isTopLevel: true
            )
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
    }

    func merge(turn: TurnAppended) {
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
            cacheHitTokens: turn.cacheHitTokens
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
                isTopLevel: false
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
    }

    func merge(usage: ProxyUsage) {
        guard let location = agentLocation(forID: usage.workerID) else { return }
        var agent = location.agent
        agent.inputTokens += usage.inputTokens
        agent.outputTokens += usage.outputTokens
        agent.cacheHitTokens += usage.cacheHitTokens
        book(
            cost: &agent,
            modelName: usage.modelName,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheHitTokens: usage.cacheHitTokens,
            reportedCostUSD: usage.reportedCostUSD
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

    func merge(balance update: BalanceUpdate) {
        switch update {
        case .loaded(let balance):
            let previous = balanceRecords[balance.provider]?.amountUSD
            balanceRecords[balance.provider] = balance
            closeBalanceWindow(for: balance.provider, previousUSD: previous, currentUSD: balance.amountUSD)
        case .unavailable(let provider, let lastPolledAt):
            balanceRecords[provider] = AccountBalance(
                provider: provider,
                amountUSD: nil,
                lastPolledAt: lastPolledAt
            )
        }
    }

    /// Turns a balance movement into spend where the provider reports one, strongest source only
    /// for DeepSeek today. The window closes on every successful poll, and a top-up only closes it:
    /// an increase is money added, never negative spend.
    private func closeBalanceWindow(for provider: String, previousUSD: Double?, currentUSD: Double?) {
        let providerKind = Provider(providerID: provider) ?? .other
        var dropUSD: Double?
        let movement = SpendAttribution.movement(
            provider: providerKind,
            previousUSD: previousUSD,
            currentUSD: currentUSD
        )
        if providerKind == .deepseek, let movement, movement.hasSpend {
            dropUSD = movement.dropUSD
        }

        var agents: [(path: String, agent: AgentRecord)] = []
        for path in workspaceRecords.keys.sorted() {
            guard let workspace = workspaceRecords[path] else { continue }
            for id in workspace.agents.keys.sorted() {
                guard let agent = workspace.agents[id],
                    Provider(providerID: agent.provider) == providerKind
                else { continue }
                agents.append((path, agent))
            }
        }
        guard agents.isEmpty == false else { return }

        var tokensByAgent: [String: Int] = [:]
        for entry in agents where entry.agent.tokensSinceBalancePoll > 0 {
            tokensByAgent[entry.agent.id] = entry.agent.tokensSinceBalancePoll
        }
        let shares = dropUSD.map { SpendAttribution.shares(dropUSD: $0, tokensByAgent: tokensByAgent) } ?? [:]

        for entry in agents {
            var agent = entry.agent
            if let share = shares[agent.id] {
                // The provider's own number replaces the local estimate for this window, so the
                // same tokens are not counted once as an estimate and again as derived spend.
                agent.costBySource.removeEstimate(agent.pendingEstimateUSD)
                agent.costBySource.add(share, source: .derived)
                agent.unpricedTokens = 0
            }
            agent.pendingEstimateUSD = 0
            agent.tokensSinceBalancePoll = 0
            replace(agent, at: entry.path)
        }
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

    /// Books one turn at the strongest source available for it. A provider-reported cost is
    /// authoritative; otherwise the local table prices it, or the turn is marked unpriced so the
    /// UI can say the cost is unavailable rather than zero.
    private func book(
        cost agent: inout AgentRecord,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        reportedCostUSD: Double? = nil
    ) {
        let tokens = inputTokens + outputTokens + cacheHitTokens
        if let reportedCostUSD {
            agent.costBySource.add(reportedCostUSD, source: .actual)
        } else if let estimate = priceBook.estimatedCostUSD(
            forModel: modelName,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheHitTokens: cacheHitTokens
        ) {
            agent.costBySource.add(estimate, source: .estimated)
            if Provider(providerID: agent.provider) == .deepseek {
                agent.pendingEstimateUSD += estimate
            }
        } else if tokens > 0 {
            agent.unpricedTokens += tokens
        }
        if Provider(providerID: agent.provider) == .deepseek {
            agent.tokensSinceBalancePoll += tokens
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
}
