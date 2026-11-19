import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

@Suite("Quota windows on the tree")
struct StoreQuotaTests {
    private func agent(_ id: String, in tree: StoreTree) -> AgentNode? {
        tree.workspaces.flatMap { [$0.orchestrator] + $0.workers }.first { $0.id == id }
    }

    private func subscriptionConfiguration(window: QuotaWindow) -> BillingConfiguration {
        BillingConfiguration(
            accounts: [
                BillingAccount(
                    id: "anthropic",
                    family: .anthropic,
                    credentialRef: "anthropic",
                    authority: .quotaWindow,
                    modelPrefixes: ["claude"]
                )
            ],
            quotaWindows: ["anthropic": window]
        )
    }

    @Test func aSubscriptionShowsAWindowAndNeverAnUnavailableBalance() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let configuration = subscriptionConfiguration(
            window: QuotaWindow(preset: .claudePro, style: .reset, interval: 5 * 3600)
        )
        let pipelines = StoreFixture.pipelines(clock: clock, billing: configuration)

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "claude-sonnet")))
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn("session-a", input: 100_000, output: 10_000, at: 1))
        )
        // The poller answers as it does for any provider with no balance endpoint.
        await pipelines.store.apply(.unavailable(provider: "anthropic", lastPolledAt: StoreFixture.date(2)))
        await pipelines.store.refresh()

        let tree = await pipelines.store.tree
        let row = try #require(tree.balances.first)
        let window = try #require(row.quotaWindow)
        #expect(row.provider == "anthropic")
        #expect(row.amountUSD == nil)
        #expect(row.unavailableReason == nil)
        #expect(row.isAvailable)
        #expect(window.usedUSD > 0)
        #expect(window.headroomUSD < window.window.limitUSD)
        #expect(window.percentUsed > 0)

        // The agent's figure is window bookkeeping, not a provider bill.
        let node = try #require(agent("session-a", in: tree))
        #expect(node.costSource == .quotaWindow)
    }

    @Test func aQuotaWindowResetsItsBurnWhenTheIntervalElapses() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let configuration = subscriptionConfiguration(
            window: QuotaWindow(preset: .claudePro, style: .reset, interval: 3600, limitUSD: 10)
        )
        let pipelines = StoreFixture.pipelines(clock: clock, billing: configuration)

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "claude-sonnet")))
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn("session-a", input: 100_000, output: 10_000, at: 1))
        )
        let before = try #require((await pipelines.store.tree).balances.first?.quotaWindow)
        #expect(before.usedUSD > 0)

        clock.advance(3 * 3600)
        await pipelines.store.refresh()

        let after = try #require((await pipelines.store.tree).balances.first?.quotaWindow)
        #expect(after.usedUSD == 0)
        #expect(abs(after.headroomUSD - 10) < 0.000_001)
    }

    @Test func aRollingWindowStartsAtTheFirstSpendAfterAReset() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let configuration = subscriptionConfiguration(
            window: QuotaWindow(preset: .claudePro, style: .rolling, interval: 3600, limitUSD: 10)
        )
        let pipelines = StoreFixture.pipelines(clock: clock, billing: configuration)

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "claude-sonnet")))
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn("session-a", input: 100_000, output: 10_000, at: 1))
        )
        // The first spend anchors the window, not the launch that created an empty one.
        let first = try #require((await pipelines.store.tree).balances.first?.quotaWindow)
        #expect(abs(first.startedAt.timeIntervalSince(StoreFixture.referenceDate)) < 0.001)

        clock.advance(2 * 3600)
        await pipelines.store.refresh()
        #expect(try #require((await pipelines.store.tree).balances.first?.quotaWindow).usedUSD == 0)

        clock.advance(600)
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn("session-a", input: 10_000, output: 1_000, at: 30))
        )
        let second = try #require((await pipelines.store.tree).balances.first?.quotaWindow)
        #expect(abs(second.startedAt.timeIntervalSince(clock.now)) < 0.001)
        #expect(second.usedUSD > 0)
    }
}
