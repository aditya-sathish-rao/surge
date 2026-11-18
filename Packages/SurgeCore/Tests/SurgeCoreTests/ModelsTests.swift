import Foundation
import SurgeCore
import Testing

struct ModelsTests {
    @Test func contextUsageRatioClampsAndHandlesZeroWindow() {
        #expect(SurgeMath.contextUsageRatio(currentContextTokens: 50, maxContextWindow: 0) == 0)
        #expect(SurgeMath.contextUsageRatio(currentContextTokens: 50, maxContextWindow: 100) == 0.5)
        #expect(SurgeMath.contextUsageRatio(currentContextTokens: 150, maxContextWindow: 100) == 1.0)
        #expect(SurgeMath.contextUsageRatio(currentContextTokens: -20, maxContextWindow: 100) == 0)
    }

    @Test func agentNodeDerivesContextLevelAndProvider() {
        let agent = AgentNode(
            id: "agent",
            provider: "DeepSeek",
            modelName: "deepseek-chat",
            status: .working,
            currentContextTokens: 96_000,
            maxContextWindow: 128_000,
            lastTokenAt: SurgeFixtures.referenceDate
        )

        #expect(agent.contextUsageRatio == 0.75)
        #expect(agent.contextLevel == .high)
        #expect(agent.providerKind == .deepseek)
    }

    @Test func workspaceTotalsAndName() {
        let workspace = SurgeFixtures.workspaces[0]

        #expect(workspace.name == "surge-widget")
        #expect(abs(workspace.totalTreeCostUSD - 0.55) < 0.000_001)
        #expect(workspace.needsYou)
    }

    @Test func statusPresentationMatchesTheDesignSystem() {
        let now = SurgeFixtures.referenceDate

        #expect(AgentStatus.working.needsYou == false)
        #expect(AgentStatus.waitingForYou.needsYou)
        #expect(AgentStatus.stalled(since: now).needsYou)
        #expect(AgentStatus.compacting.needsYou == false)
        #expect(AgentStatus.idle(since: now).needsYou == false)
        #expect(AgentStatus.done.needsYou == false)
        #expect(AgentStatus.noSignal.needsYou == false)

        #expect(AgentStatus.working.symbol == "bolt.fill")
        #expect(AgentStatus.waitingForYou.symbol == "hand.raised.fill")
        #expect(AgentStatus.stalled(since: now).symbol == "exclamationmark.triangle.fill")
        #expect(AgentStatus.compacting.symbol == "arrow.down.and.line.horizontal.and.arrow.up")
        #expect(AgentStatus.idle(since: now).symbol == "pause.fill")
        #expect(AgentStatus.done.symbol == "checkmark")
        #expect(AgentStatus.noSignal.symbol == "bolt.slash")
    }

    @Test func providerResolvesKnownIDsAndRejectsUnknownOnes() {
        #expect(Provider(providerID: "anthropic") == .anthropic)
        #expect(Provider(providerID: "DeepSeek") == .deepseek)
        #expect(Provider(providerID: "openrouter") == .openrouter)
        #expect(Provider(providerID: "other") == .other)
        #expect(Provider(providerID: "gemini") == nil)
        #expect(Provider.other.name == "Other")
    }

    @Test func thresholdsMapRatiosAndBalances() {
        #expect(SurgeThresholds.contextLevel(forRatio: 0.699) == .normal)
        #expect(SurgeThresholds.contextLevel(forRatio: 0.70) == .high)
        #expect(SurgeThresholds.contextLevel(forRatio: 0.899) == .high)
        #expect(SurgeThresholds.contextLevel(forRatio: 0.90) == .nearLimit)
        #expect(SurgeThresholds.contextLevel(forRatio: 1.4) == .nearLimit)

        #expect(SurgeThresholds.balanceLevel(forUSD: 0.49) == .empty)
        #expect(SurgeThresholds.balanceLevel(forUSD: 0.50) == .low)
        #expect(SurgeThresholds.balanceLevel(forUSD: 4.99) == .low)
        #expect(SurgeThresholds.balanceLevel(forUSD: 5.00) == .normal)
    }

    @Test func accountBalanceExposesAvailabilityAndLevel() {
        let unavailable = AccountBalance(
            provider: "anthropic", amountUSD: nil, lastPolledAt: SurgeFixtures.referenceDate)
        let low = AccountBalance(provider: "openrouter", amountUSD: 3.20, lastPolledAt: SurgeFixtures.referenceDate)

        #expect(unavailable.isAvailable == false)
        #expect(unavailable.level == nil)
        #expect(low.isAvailable)
        #expect(low.level == .low)
        #expect(low.providerKind == .openrouter)
    }
}
