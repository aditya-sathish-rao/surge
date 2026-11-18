import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

struct DerivedStateTests {
    // MARK: - Stall detection

    @Test func stallFlipsExactlyWhenTheThresholdPasses() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))

        clock.advance(119)
        await harness.store.refresh()
        var tree = await harness.store.tree
        #expect(tree.workspaces.first?.orchestrator.status == .working)

        clock.advance(1)
        await harness.store.refresh()
        tree = await harness.store.tree
        #expect(tree.workspaces.first?.orchestrator.status == .stalled(since: StoreFixture.date(0)))
    }

    @Test func aFreshTurnClearsAStall() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))

        clock.advance(200)
        await harness.store.refresh()
        var tree = await harness.store.tree
        #expect(tree.workspaces.first?.orchestrator.status.needsYou == true)

        await harness.store.apply(.turnAppended(StoreFixture.turn(output: 10, at: 200)))
        tree = await harness.store.tree
        #expect(tree.workspaces.first?.orchestrator.status == .working)
    }

    @Test func aReasoningModelUsesItsLongerThreshold() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.apply(
            .workerAppeared(StoreFixture.worker(model: "deepseek-reasoner", at: 0))
        )

        clock.advance(120)
        await harness.store.refresh()
        var tree = await harness.store.tree
        #expect(tree.workspaces.first?.workers.first?.status == .working)

        clock.advance(180)
        await harness.store.refresh()
        tree = await harness.store.tree
        #expect(tree.workspaces.first?.workers.first?.status == .stalled(since: StoreFixture.date(0)))
    }

    @Test func waitingForYouNeverStalls() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.record(.waitingForYou, for: "session-a", at: StoreFixture.date(10))

        clock.advance(1_000)
        await harness.store.refresh()

        let tree = await harness.store.tree
        #expect(tree.workspaces.first?.orchestrator.status == .waitingForYou)
    }

    // MARK: - Done window

    @Test func aDoneAgentStaysForTenMinutesThenExpires() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.apply(.sessionEnded(sessionID: "session-a", occurredAt: StoreFixture.date(60)))

        clock.advance(659)
        await harness.store.refresh()
        var tree = await harness.store.tree
        #expect(tree.workspaces.first?.orchestrator.status == .done)

        clock.advance(2)
        await harness.store.refresh()
        tree = await harness.store.tree
        #expect(tree.workspaces.isEmpty)
    }

    @Test func aWorkerIsPromotedWhenTheOrchestratorExpires() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.apply(.workerAppeared(StoreFixture.worker(at: 0)))
        await harness.store.apply(.sessionEnded(sessionID: "session-a", occurredAt: StoreFixture.date(60)))

        clock.advance(661)
        await harness.store.refresh()

        let tree = await harness.store.tree
        let workspace = try #require(tree.workspaces.first)
        #expect(workspace.orchestrator.id == "worker-1")
        #expect(workspace.workers.isEmpty)
    }

    // MARK: - Sorting

    @Test func workspacesNeedingAttentionSortFirstThenBySpend() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-alpha", path: "/code/alpha")))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn("session-alpha", output: 20_000, at: 190))
        )
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-beta", path: "/code/beta")))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn("session-beta", output: 40_000, at: 0))
        )
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-gamma", path: "/code/gamma")))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn("session-gamma", output: 10_000, at: 195))
        )
        await harness.store.record(.waitingForYou, for: "session-gamma", at: StoreFixture.date(196))

        clock.advance(200)
        await harness.store.refresh()

        let tree = await harness.store.tree
        #expect(tree.workspaces.map(\.projectPath) == ["/code/beta", "/code/gamma", "/code/alpha"])
        #expect(tree.workspaces.map(\.needsYou) == [true, true, false])
    }

    @Test func workspaceSortFallsBackToPathForTies() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-beta", path: "/code/beta")))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn("session-beta", output: 20_000, at: 190))
        )
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-alpha", path: "/code/alpha")))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn("session-alpha", output: 20_000, at: 190))
        )
        await harness.store.record(.waitingForYou, for: "session-alpha", at: StoreFixture.date(191))
        await harness.store.record(.waitingForYou, for: "session-beta", at: StoreFixture.date(191))

        clock.advance(200)
        await harness.store.refresh()

        let tree = await harness.store.tree
        #expect(tree.workspaces.map(\.projectPath) == ["/code/alpha", "/code/beta"])
    }

    @Test func agentsNeedingAttentionSortFirstAndKeepTheirSubAgentsBesideThem() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-o", at: 0)))
        await harness.store.apply(.turnAppended(StoreFixture.turn("session-o", output: 10, at: 190)))
        await harness.store.apply(.workerAppeared(StoreFixture.worker("worker-o1", parent: "session-o", at: 5)))
        await harness.store.apply(.usage(StoreFixture.usage("worker-o1", output: 10, at: 190)))
        await harness.store.apply(.workerAppeared(StoreFixture.worker("worker-o2", parent: "session-o", at: 6)))
        await harness.store.record(.waitingForYou, for: "worker-o2", at: StoreFixture.date(191))
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-p", at: 7)))
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-q", at: 8)))
        await harness.store.apply(.turnAppended(StoreFixture.turn("session-q", output: 10, at: 190)))
        await harness.store.apply(.workerAppeared(StoreFixture.worker("worker-p1", parent: "session-p", at: 9)))

        clock.advance(200)
        await harness.store.refresh()

        let tree = await harness.store.tree
        let workspace = try #require(tree.workspaces.first)
        #expect(workspace.orchestrator.id == "session-o")
        #expect(workspace.workers.map(\.id) == ["worker-o2", "worker-o1", "session-p", "worker-p1", "session-q"])
    }

    // MARK: - Totals and attention

    @Test func workspaceCostTotalsAndAttentionCounts() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn(output: 20_000, context: 10_000, at: 10))
        )
        await harness.store.apply(.workerAppeared(StoreFixture.worker(at: 5)))
        await harness.store.apply(
            .usage(StoreFixture.usage(output: 10_000, context: 4_000, at: 20))
        )
        await harness.store.record(.waitingForYou, for: "worker-1", at: StoreFixture.date(30))

        let tree = await harness.store.tree
        let workspace = try #require(tree.workspaces.first)
        // 20,000 output tokens of claude-sonnet at $15/M, 10,000 of deepseek-chat at $1.10/M.
        #expect(abs(workspace.totalTreeCostUSD - (0.30 + 0.011)) < 0.000_001)
        #expect(abs(tree.totalSpendUSD - (0.30 + 0.011)) < 0.000_001)
        #expect(workspace.orchestrator.status == .working)
        #expect(workspace.workers.first?.status == .waitingForYou)
        #expect(workspace.needsYou == true)
        #expect(tree.attentionCount == 1)
        #expect(tree.attentionCount(forWorkspace: workspace.id) == 1)
        #expect(tree.orchestratorCount == 1)
        #expect(tree.workerCount == 1)
    }

    // MARK: - Balances

    @Test func configuredBalanceThresholdsChooseLowAndEmpty() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(
            clock: clock,
            thresholds: BalanceThresholds(lowUSD: 5, emptyUSD: 0.50)
        )

        await harness.store.apply(.loaded(StoreFixture.balance("anthropic", amount: 5.00)))
        await harness.store.apply(.loaded(StoreFixture.balance("deepseek", amount: 4.99)))
        await harness.store.apply(.loaded(StoreFixture.balance("openrouter", amount: 0.49)))

        let tree = await harness.store.tree
        #expect(tree.balances.map(\.provider) == ["anthropic", "deepseek", "openrouter"])
        #expect(tree.balanceLevel(forProvider: "anthropic") == .normal)
        #expect(tree.balanceLevel(forProvider: "deepseek") == .low)
        #expect(tree.balanceLevel(forProvider: "openrouter") == .empty)
        #expect(tree.balanceLevel(forProvider: "unknown") == nil)
    }

    @Test func customBalanceThresholdsAreUsed() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(
            clock: clock,
            thresholds: BalanceThresholds(lowUSD: 10, emptyUSD: 1)
        )

        await harness.store.apply(.loaded(StoreFixture.balance("deepseek", amount: 9.99)))
        await harness.store.apply(.loaded(StoreFixture.balance("openrouter", amount: 0.99)))

        let tree = await harness.store.tree
        #expect(tree.balanceLevel(forProvider: "deepseek") == .low)
        #expect(tree.balanceLevel(forProvider: "openrouter") == .empty)
    }

    @Test func anUnavailableBalanceKeepsItsRowWithoutAnAmount() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.loaded(StoreFixture.balance("deepseek", amount: 12.40)))
        await harness.store.apply(
            .unavailable(provider: "deepseek", lastPolledAt: StoreFixture.date(60))
        )

        let tree = await harness.store.tree
        let balance = tree.balances.first
        #expect(balance?.provider == "deepseek")
        #expect(balance?.amountUSD == nil)
        #expect(balance?.lastPolledAt == StoreFixture.date(60))
        #expect(tree.balanceLevel(forProvider: "deepseek") == nil)
    }
}
