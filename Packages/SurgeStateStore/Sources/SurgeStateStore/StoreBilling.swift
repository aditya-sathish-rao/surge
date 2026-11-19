import Foundation
import SurgeCore

// MARK: - Billing attribution

extension SurgeStateStore {
    /// The top of the session tree an agent belongs to. A session with no parent is its own root.
    func treeRoot(forAgentID id: String) -> AgentLocation? {
        guard var current = agentLocation(forID: id) else { return nil }
        var visited: Set<String> = [current.agent.id]
        while let parentID = current.agent.parentSessionID {
            guard let parent = agentLocation(forID: parentID),
                visited.insert(parent.agent.id).inserted
            else { return current }
            current = parent
        }
        return current
    }

    /// Resolves an account once for the tree and hands the result to every agent in it.
    ///
    /// The root's harness and model decide, so a sub-agent never resolves its own account. When the
    /// root has already resolved, its answer is simply applied to the rest of the tree.
    func resolveAttributionIfNeeded(forAgentID id: String) {
        guard let root = treeRoot(forAgentID: id) else { return }
        let attribution =
            root.agent.attribution
            ?? BillingResolver.attribution(
                harness: root.agent.harness?.kind ?? .generic,
                modelName: root.agent.modelName,
                configuration: billing
            )
        apply(attribution, toTreeRootedAt: root.agent.id)
    }

    func apply(_ attribution: BillingAttribution, toTreeRootedAt rootID: String) {
        for location in allAgentLocations() {
            guard location.agent.attribution != attribution,
                treeRoot(forAgentID: location.agent.id)?.agent.id == rootID
            else { continue }
            var agent = location.agent
            agent.attribution = attribution
            replace(agent, at: location.projectPath)
        }
    }

    /// Re-resolves every tree after the user changes an account or a binding in Settings.
    func rebuildAttributions() {
        for location in allAgentLocations() {
            var agent = location.agent
            agent.attribution = nil
            replace(agent, at: location.projectPath)
        }
        let roots = allAgentLocations().filter {
            treeRoot(forAgentID: $0.agent.id)?.agent.id == $0.agent.id
        }
        for location in roots {
            resolveAttributionIfNeeded(forAgentID: location.agent.id)
        }
        pruneQuotaStates()
    }

    // MARK: - Booking

    /// Books one turn at the strongest source its attribution allows.
    ///
    /// The figure and its label come from `BillingResolver`, so the precedence rules live in one
    /// place. A turn nothing could price is marked unpriced so the UI says unavailable, not free.
    func book(
        cost agent: inout AgentRecord,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        providerReportedUSD: Double? = nil,
        harnessReportedCumulativeUSD: Double? = nil
    ) {
        let tokens = inputTokens + outputTokens + cacheHitTokens
        let estimate = priceBook.estimatedCostUSD(
            forModel: modelName,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheHitTokens: cacheHitTokens
        )
        let figures = TurnFigures(
            providerReportedUSD: providerReportedUSD,
            harnessReportedUSD: harnessIncrease(&agent, cumulative: harnessReportedCumulativeUSD),
            estimateUSD: estimate
        )
        if let booked = BillingResolver.book(figures, attribution: agent.attribution ?? .none) {
            agent.costBySource.add(booked.amountUSD, source: booked.source)
            if agent.balanceDerivedAccountID != nil {
                agent.windowSpend.add(booked.amountUSD, source: booked.source)
            }
            if let account = agent.billingAccount, account.authority == .quotaWindow {
                bookToQuotaWindow(accountID: account.id, amount: booked.amountUSD)
            }
        } else if tokens > 0 {
            agent.unpricedTokens += tokens
        }
        if agent.balanceDerivedAccountID != nil {
            agent.tokensSinceBalancePoll += tokens
        }
    }

    /// The harness reports a running total, so only the increase is new spend. A total that moved
    /// backwards is a restarted counter, not a refund, so the baseline resets and nothing is booked.
    private func harnessIncrease(_ agent: inout AgentRecord, cumulative: Double?) -> Double? {
        guard let cumulative else { return nil }
        let previous = agent.lastHarnessCumulativeUSD ?? 0
        agent.lastHarnessCumulativeUSD = cumulative
        let increase = cumulative - previous
        return increase > 0 ? increase : nil
    }

    // MARK: - Balance movement

    func merge(balance update: BalanceUpdate) {
        switch update {
        case .loaded(let balance):
            guard !isQuotaAccount(balance.provider) else {
                // A subscription reports no balance. The window is the only row it has.
                quotaPollDates[balance.provider] = balance.lastPolledAt
                return
            }
            let previous = lastKnownBalancesUSD[balance.provider]
            balanceRecords[balance.provider] = balance
            // A poll that answered without an amount (a refused key, an odd response) says nothing
            // about what was spent. Only a real figure may move the baseline or close the window,
            // or the tokens spent while the poll was failing would lose their share of the next drop.
            guard let amount = balance.amountUSD else { return }
            lastKnownBalancesUSD[balance.provider] = amount
            closeBalanceWindow(
                accountID: balance.provider,
                previousUSD: previous,
                currentUSD: amount
            )
        case .unavailable(let provider, let lastPolledAt):
            guard !isQuotaAccount(provider) else { return }
            balanceRecords[provider] = AccountBalance(
                provider: provider,
                amountUSD: nil,
                lastPolledAt: lastPolledAt
            )
        }
    }

    /// Turns a balance movement into spend for every account whose provider reports no per-turn
    /// cost. A top-up only closes the window: an increase is money added, never negative spend.
    private func closeBalanceWindow(accountID: String, previousUSD: Double?, currentUSD: Double?) {
        guard let account = billing.account(withID: accountID), account.authority == .balanceDerived else { return }
        let movement = SpendAttribution.movement(
            provider: account.family,
            previousUSD: previousUSD,
            currentUSD: currentUSD
        )
        let agents = allAgentLocations().filter { $0.agent.billingAccount?.id == accountID }
        guard agents.isEmpty == false else { return }

        var tokensByAgent: [String: Int] = [:]
        for entry in agents where entry.agent.tokensSinceBalancePoll > 0 {
            tokensByAgent[entry.agent.id] = entry.agent.tokensSinceBalancePoll
        }
        let shares =
            movement?.hasSpend == true
            ? SpendAttribution.shares(dropUSD: movement?.dropUSD ?? 0, tokensByAgent: tokensByAgent)
            : [:]

        for entry in agents {
            var agent = entry.agent
            if let share = shares[agent.id] {
                // The observed drop replaces exactly what this window booked, so the same tokens
                // are never counted once as an estimate and again as derived spend.
                agent.costBySource.remove(agent.windowSpend)
                agent.costBySource.add(share, source: .balanceDerived)
                agent.unpricedTokens = 0
            }
            agent.windowSpend = SpendBySource()
            agent.tokensSinceBalancePoll = 0
            replace(agent, at: entry.projectPath)
        }
    }

    // MARK: - Quota windows

    func isQuotaAccount(_ accountID: String) -> Bool {
        billing.account(withID: accountID)?.authority == .quotaWindow
    }

    private func bookToQuotaWindow(accountID: String, amount: Double) {
        let now = self.clock()
        guard amount > 0, let window = billing.quotaWindow(forAccount: accountID) else { return }
        var state = quotaStates[accountID] ?? QuotaWindowState(window: window, startedAt: now)
        state.advance(to: now)
        // A rolling plan window starts at the first message after a gap, not at launch, so its
        // reset is measured from the first spend in an empty window.
        if window.style == .rolling, state.usedUSD == 0 {
            state = QuotaWindowState(window: window, startedAt: now)
        }
        state.book(amount)
        quotaStates[accountID] = state
    }

    /// One row per subscription account, rebuilt on every publish so a reset lands even when no
    /// spend arrives. A quota row always has a figure, so it never reads as an unavailable balance.
    func quotaBalances(now: Date) -> [AccountBalance] {
        var rows: [AccountBalance] = []
        for account in billing.quotaAccounts {
            guard let window = billing.quotaWindow(forAccount: account.id) else { continue }
            var state = quotaStates[account.id] ?? QuotaWindowState(window: window, startedAt: now)
            if state.window != window {
                // Settings changed the ceiling or the interval. The burn so far stays.
                state = QuotaWindowState(
                    window: window,
                    startedAt: min(state.startedAt, now),
                    spentUSD: state.spentUSD
                )
            }
            state.advance(to: now)
            quotaStates[account.id] = state
            rows.append(
                AccountBalance(
                    provider: account.id,
                    amountUSD: nil,
                    lastPolledAt: quotaPollDates[account.id] ?? now,
                    quotaWindow: state
                )
            )
        }
        return rows
    }

    func pruneQuotaStates() {
        for accountID in quotaStates.keys where !isQuotaAccount(accountID) {
            quotaStates[accountID] = nil
        }
        for accountID in quotaPollDates.keys where !isQuotaAccount(accountID) {
            quotaPollDates[accountID] = nil
        }
    }
}
