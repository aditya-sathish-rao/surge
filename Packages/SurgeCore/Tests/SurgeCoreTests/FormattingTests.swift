import Foundation
import SurgeCore
import Testing

struct FormattingTests {
    private let now = SurgeFixtures.referenceDate

    @Test func costUsesUSDDollars() {
        #expect(SurgeFormatting.cost(1.42) == "$1.42")
        #expect(SurgeFormatting.cost(12.4) == "$12.40")
    }

    @Test func contextPercentRoundsAndClamps() {
        #expect(SurgeFormatting.percent(0.705) == "71%")
        #expect(SurgeFormatting.percent(-0.2) == "0%")
        #expect(SurgeFormatting.percent(1.4) == "100%")
    }

    @Test func tokenRateRoundsToWholeTokens() {
        #expect(SurgeFormatting.tokenRate(411.6) == "412 tok/s")
        #expect(SurgeFormatting.tokenRate(-3) == "0 tok/s")
    }

    @Test func durationsReadTheWayTheDesignFileSpecifies() {
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-42), now: now) == "42s")
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-240), now: now) == "4m")
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-194), now: now) == "3m 14s")
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-7_200), now: now) == "2h 0m")
        #expect(SurgeFormatting.minutesDuration(since: now.addingTimeInterval(-2_520), now: now) == "42m")
    }

    @Test func statusLabelsCarryWordsAndElapsedTime() {
        #expect(SurgeFormatting.statusLabel(.working, now: now) == "Working")
        #expect(SurgeFormatting.statusLabel(.waitingForYou, now: now) == "Waiting for you")
        #expect(SurgeFormatting.statusLabel(.compacting, now: now) == "Compacting")
        #expect(SurgeFormatting.statusLabel(.noSignal, now: now) == "No signal")
        #expect(
            SurgeFormatting.statusLabel(.stalled(since: now.addingTimeInterval(-194)), now: now) == "Stalled 3m 14s"
        )
        #expect(SurgeFormatting.statusLabel(.idle(since: now.addingTimeInterval(-240)), now: now) == "Idle 4m")
        #expect(
            SurgeFormatting.statusLabel(.done, now: now, lastActivityAt: now.addingTimeInterval(-2_520)) == "Done · 42m"
        )
        #expect(SurgeFormatting.statusLabel(.done, now: now) == "Done")
    }

    @Test func balanceLabelDistinguishesLowEmptyAndUnavailable() {
        let low = AccountBalance(provider: "openrouter", amountUSD: 3.20, lastPolledAt: now)
        let empty = AccountBalance(provider: "openrouter", amountUSD: 0.20, lastPolledAt: now)
        let healthy = AccountBalance(provider: "deepseek", amountUSD: 12.40, lastPolledAt: now)
        let unavailable = AccountBalance(provider: "anthropic", amountUSD: nil, lastPolledAt: now)

        #expect(SurgeFormatting.balanceLabel(low) == "$3.20 · Low")
        #expect(SurgeFormatting.balanceLabel(empty) == "$0.20 · Empty")
        #expect(SurgeFormatting.balanceLabel(healthy) == "$12.40")
        #expect(SurgeFormatting.balanceLabel(unavailable) == "Balance unavailable")
    }

    @Test func menuBarReadoutKeepsTheLabelWithTheNumber() {
        #expect(
            SurgeFormatting.menuBarReadout(
                orchestrators: 1,
                workers: 2,
                spend: SpendFigure(amountUSD: 1.42, source: .estimated)
            ) == "1 Orch, 2 Workers, $1.42 est.")
        #expect(
            SurgeFormatting.menuBarReadout(
                orchestrators: 2,
                workers: 1,
                spend: SpendFigure(amountUSD: 0, source: .estimated)
            ) == "2 Orchs, 1 Worker, $0.00 est.")
    }

    @Test func menuBarSummaryReadsThePRDShapeWithoutJargon() {
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 1,
                workers: 2,
                spend: SpendFigure(amountUSD: 1.42, source: .estimated)
            ) == "1 Orch, 2 Workers, $1.42")
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 2,
                workers: 1,
                spend: SpendFigure(amountUSD: 2.10, source: .balanceDerived)
            ) == "2 Orchs, 1 Worker, $2.10")
    }

    @Test func menuBarSummaryLeavesOutZeroCountsAndUnreportableSpend() {
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 4,
                workers: 0,
                spend: SpendFigure(amountUSD: 4.58, source: .providerReported)
            ) == "4 Orchs, $4.58")
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 3,
                workers: 0,
                spend: SpendFigure(amountUSD: 0, source: .estimated)
            ) == "3 Orchs, $0.00")
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 0,
                workers: 0,
                spend: SpendFigure(amountUSD: 5, source: .providerReported)
            ) == "$5.00")
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 0,
                workers: 0,
                spend: SpendFigure(amountUSD: 0, source: .estimated)
            ) == nil)
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 0,
                workers: 0,
                spend: SpendFigure(amountUSD: 0.004, source: .estimated)
            ) == nil)
        #expect(
            SurgeFormatting.menuBarSummary(
                orchestrators: 1,
                workers: 0,
                spend: SpendFigure(amountUSD: 0, source: .unavailable)
            ) == "1 Orch")
    }

    @Test func menuBarSpendAppearsOnlyWhenThereIsSomethingToSay() {
        #expect(
            !SurgeFormatting.menuBarShowsSpend(
                agentCount: 0,
                spend: SpendFigure(amountUSD: 0, source: .estimated)
            ))
        #expect(
            !SurgeFormatting.menuBarShowsSpend(
                agentCount: 0,
                spend: SpendFigure(amountUSD: 0.004, source: .estimated)
            ))
        #expect(
            !SurgeFormatting.menuBarShowsSpend(
                agentCount: 2,
                spend: SpendFigure(amountUSD: 0, source: .unavailable)
            ))
        #expect(
            SurgeFormatting.menuBarShowsSpend(
                agentCount: 0,
                spend: SpendFigure(amountUSD: 5, source: .providerReported)
            ))
        #expect(
            SurgeFormatting.menuBarShowsSpend(
                agentCount: 2,
                spend: SpendFigure(amountUSD: 0, source: .estimated)
            ))
    }

    @Test func menuBarRunDescriptionAlwaysSpeaksTheAgentCountAndOneAttentionClause() {
        #expect(SurgeFormatting.menuBarRunDescription(agentCount: 1, attentionCount: 1) == "1 agent needs you")
        #expect(SurgeFormatting.menuBarRunDescription(agentCount: 5, attentionCount: 1) == "5 agents, 1 needs you")
        #expect(SurgeFormatting.menuBarRunDescription(agentCount: 6, attentionCount: 2) == "6 agents, 2 need you")
        #expect(SurgeFormatting.menuBarRunDescription(agentCount: 5, attentionCount: 0) == "5 agents")
        #expect(SurgeFormatting.menuBarRunDescription(agentCount: 1, attentionCount: 0) == "1 agent")
        #expect(SurgeFormatting.menuBarRunDescription(agentCount: 0, attentionCount: 0) == "No agents running")
    }

    @Test func spokenUSDReadsMoneyWithoutPaddedCents() {
        #expect(SurgeFormatting.spokenUSD(0) == "0 dollars")
        #expect(SurgeFormatting.spokenUSD(0.01) == "1 cent")
        #expect(SurgeFormatting.spokenUSD(0.05) == "5 cents")
        #expect(SurgeFormatting.spokenUSD(1) == "1 dollar")
        #expect(SurgeFormatting.spokenUSD(16.05) == "16 dollars 5 cents")
        #expect(SurgeFormatting.spokenUSD(16.91) == "16 dollars 91")
    }
}
