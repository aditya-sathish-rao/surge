import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

@Suite("Billing on the tree")
struct StoreBillingTests {
    private func agents(in tree: StoreTree) -> [AgentNode] {
        tree.workspaces.flatMap { [$0.orchestrator] + $0.workers }
    }

    private func agent(_ id: String, in tree: StoreTree) -> AgentNode? {
        agents(in: tree).first { $0.id == id }
    }

    private func routerBoundConfiguration() -> BillingConfiguration {
        BillingConfiguration(
            accounts: BillingAccount.standard,
            bindings: [
                BillingBinding(harness: .claudeCode, modelPrefix: "claude", accountID: "openrouter")
            ]
        )
    }

    @Test func aSessionCarriesItsHarnessAndTheAccountThatPays() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "claude-sonnet")))
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn("session-a", input: 1_000, output: 100, at: 1))
        )

        let node = try #require(agent("session-a", in: await pipelines.store.tree))
        #expect(node.harness?.kind == .claudeCode)
        #expect(node.harness?.transport == .jsonl)
        #expect(node.billingAccount?.id == "anthropic")
    }

    @Test func anExplicitRouterBindingLabelsTheCostButKeepsTheAccount() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock, billing: routerBoundConfiguration())

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a")))
        // Claude Code's own running total, at Anthropic list prices.
        await pipelines.store.apply(
            .turnAppended(
                StoreFixture.turn("session-a", input: 1_000, output: 100, at: 1, harnessReportedCostUSD: 0.055)
            )
        )

        let node = try #require(agent("session-a", in: await pipelines.store.tree))
        #expect(node.billingAccount?.id == "openrouter")
        #expect(node.costSource == .harnessReported)
        #expect(abs(node.estimatedCostUSD - 0.055) < 0.000_001)
    }

    @Test func aProviderReportedCostOutranksTheHarnessFigureOnARouterBinding() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock, billing: routerBoundConfiguration())

        // A worker the router billed exactly, on a model Claude Code priced higher.
        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a")))
        await pipelines.store.apply(
            .workerAppeared(
                StoreFixture.worker("worker-1", model: "claude-sonnet", provider: "openrouter", parent: "session-a")
            )
        )
        await pipelines.store.apply(
            .usage(
                StoreFixture.usage(
                    "worker-1",
                    model: "claude-sonnet",
                    provider: "openrouter",
                    input: 1_000,
                    at: 1,
                    reportedCostUSD: 0.0412
                )
            )
        )

        let node = try #require(agent("worker-1", in: await pipelines.store.tree))
        #expect(node.costSource == .providerReported)
        #expect(abs(node.estimatedCostUSD - 0.0412) < 0.000_001)
        // The worker inherited the session tree's account instead of matching its own model.
        #expect(node.billingAccount?.id == "openrouter")
    }

    @Test func twoMatchingAccountsLeaveTheSpendUnattributedAndMarkItHarnessReported() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let twoDeepSeek = BillingConfiguration(
            accounts: [
                BillingAccount(
                    id: "deepseek-personal",
                    family: .deepseek,
                    credentialRef: "deepseek",
                    authority: .balanceDerived,
                    modelPrefixes: ["deepseek"]
                ),
                BillingAccount(
                    id: "deepseek-work",
                    family: .deepseek,
                    credentialRef: "deepseek",
                    authority: .balanceDerived,
                    modelPrefixes: ["deepseek"]
                ),
            ]
        )
        let pipelines = StoreFixture.pipelines(clock: clock, billing: twoDeepSeek)

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "deepseek-chat")))
        await pipelines.store.apply(
            .turnAppended(
                StoreFixture.turn(
                    "session-a",
                    model: "deepseek-chat",
                    input: 1_000,
                    output: 100,
                    at: 1,
                    harnessReportedCostUSD: 0.42
                )
            )
        )

        let node = try #require(agent("session-a", in: await pipelines.store.tree))
        #expect(node.billingAccount == nil)
        #expect(node.costSource == .harnessReported)
        #expect(abs(node.estimatedCostUSD - 0.42) < 0.000_001)
    }

    @Test func aSubAgentInheritsTheAccountItsSessionResolved() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock, billing: routerBoundConfiguration())

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "claude-sonnet")))
        // The sub-agent runs a DeepSeek model, which would resolve to the DeepSeek account on its
        // own. It inherits the OpenRouter binding from the session that spawned it instead.
        await pipelines.store.apply(
            .sessionAppeared(
                StoreFixture.session(
                    "sub-1",
                    model: "deepseek-chat",
                    provider: "deepseek",
                    parent: "session-a",
                    at: 1
                )
            )
        )
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn("sub-1", model: "deepseek-chat", input: 1_000, at: 2))
        )

        let tree = await pipelines.store.tree
        let subAgent = try #require(agent("sub-1", in: tree))
        #expect(subAgent.billingAccount?.id == "openrouter")
        // The session the sub-agent belongs to is the orchestrator, not a peer.
        let workspace = try #require(tree.workspaces.first)
        #expect(workspace.orchestrator.id == "session-a")
        #expect(workspace.workers.map(\.id) == ["sub-1"])
    }

    @Test func aSubAgentThatArrivesFirstPicksUpItsParentsAccountWhenItAppears() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock, billing: routerBoundConfiguration())

        await pipelines.store.apply(
            .sessionAppeared(
                StoreFixture.session(
                    "sub-1",
                    model: "deepseek-chat",
                    provider: "deepseek",
                    parent: "session-a"
                )
            )
        )
        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "claude-sonnet", at: 1)))

        let node = try #require(agent("sub-1", in: await pipelines.store.tree))
        #expect(node.billingAccount?.id == "openrouter")
    }

    @Test func aRepeatedTurnIDIsCountedOnceAcrossTheTree() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a")))
        let turn = StoreFixture.turn("session-a", input: 2_000, output: 200, at: 1, eventID: "msg-1")
        await pipelines.store.apply(.turnAppended(turn))
        await pipelines.store.apply(.turnAppended(turn))

        // The same id written again from a sub-agent file must not add tokens twice either.
        await pipelines.store.apply(
            .sessionAppeared(StoreFixture.session("sub-1", parent: "session-a", at: 1.5))
        )
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn("sub-1", model: "claude-sonnet", input: 2_000, at: 2, eventID: "msg-1"))
        )

        let node = try #require(agent("session-a", in: await pipelines.store.tree))
        #expect(node.inputTokens == 2_000)
        #expect(node.outputTokens == 200)
    }

    @Test func anUnpricedDeepSeekTurnGetsItsSpendFromTheBalanceDrop() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)

        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "deepseek-unlisted", provider: "deepseek"))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.40, at: 0)))
        await pipelines.store.apply(
            .usage(StoreFixture.usage("worker-1", model: "deepseek-unlisted", input: 6_000, at: 1))
        )
        // The price table does not know this model, so nothing can be estimated yet.
        let beforePoll = try #require(agent("worker-1", in: await pipelines.store.tree))
        #expect(beforePoll.costSource == nil)
        #expect(beforePoll.estimatedCostUSD == 0)

        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.10, at: 60)))

        let afterPoll = try #require(agent("worker-1", in: await pipelines.store.tree))
        #expect(afterPoll.costSource == .balanceDerived)
        #expect(abs(afterPoll.estimatedCostUSD - 0.30) < 0.000_001)
        // The state store now has a real figure for today's spend to book.
        let workspace = try #require((await pipelines.store.tree).workspaces.first)
        #expect(workspace.spendFigure?.source == .balanceDerived)
        #expect(abs((workspace.spendFigure?.amountUSD ?? 0) - 0.30) < 0.000_001)
    }

    @Test func aPollThatAnswersWithoutAnAmountKeepsTheWindowOpen() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)

        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "deepseek-chat", provider: "deepseek"))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.40, at: 0)))
        await pipelines.store.apply(.usage(StoreFixture.usage("worker-1", input: 3_000, at: 1)))
        // The key read failed, so the provider answered with no amount. That is not a movement.
        await pipelines.store.apply(
            .loaded(StoreFixture.unavailableBalance("deepseek", reason: .keyUnavailable, at: 30))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.20, at: 60)))

        let node = try #require(agent("worker-1", in: await pipelines.store.tree))
        #expect(node.costSource == .balanceDerived)
        #expect(abs(node.estimatedCostUSD - 0.20) < 0.000_001)
    }

    @Test func aDerivedFigureNeverTurnsBackIntoUnavailableWhileTheNextWindowIsOpen() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)

        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "deepseek-unlisted", provider: "deepseek"))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.40, at: 0)))
        await pipelines.store.apply(
            .usage(StoreFixture.usage("worker-1", model: "deepseek-unlisted", input: 6_000, at: 1)))
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.10, at: 60)))
        #expect(try #require(agent("worker-1", in: await pipelines.store.tree)).costSource == .balanceDerived)

        // More unpriced tokens arrive before the next poll. They wait for the next movement rather
        // than turning the last real figure back into unavailable.
        await pipelines.store.apply(
            .usage(StoreFixture.usage("worker-1", model: "deepseek-unlisted", input: 2_000, at: 61)))

        let node = try #require(agent("worker-1", in: await pipelines.store.tree))
        #expect(node.costSource == .balanceDerived)
        #expect(abs(node.estimatedCostUSD - 0.30) < 0.000_001)
    }

    @Test func spendStaysWithTheAccountThatWasCharged() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)

        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "deepseek-chat", provider: "deepseek"))
        )
        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-2", model: "openrouter-auto", provider: "openrouter"))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.40, at: 0)))
        await pipelines.store.apply(.usage(StoreFixture.usage("worker-1", input: 3_000, at: 1)))
        // OpenRouter's balance row moves too. It is not a balance-derived account, so its spend
        // never comes from this movement.
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("openrouter", amount: 3.00, at: 30)))
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.20, at: 60)))

        let tree = await pipelines.store.tree
        let deepSeek = try #require(agent("worker-1", in: tree))
        let openRouter = try #require(agent("worker-2", in: tree))
        #expect(deepSeek.costSource == .balanceDerived)
        #expect(openRouter.costSource != .balanceDerived)
    }

    @Test func changingTheBindingReResolvesTheSessionsAlreadyOnScreen() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)

        await pipelines.store.apply(.sessionAppeared(StoreFixture.session("session-a", model: "claude-sonnet")))
        #expect(try #require(agent("session-a", in: await pipelines.store.tree)).billingAccount?.id == "anthropic")

        await pipelines.store.updateBilling(routerBoundConfiguration())

        #expect(try #require(agent("session-a", in: await pipelines.store.tree)).billingAccount?.id == "openrouter")
    }
}
