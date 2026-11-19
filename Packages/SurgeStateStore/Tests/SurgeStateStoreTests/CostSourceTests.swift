import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

@Suite("Cost sources")
struct CostSourceTests {
    private func agents(in tree: StoreTree) -> [AgentNode] {
        tree.workspaces.flatMap { [$0.orchestrator] + $0.workers }
    }

    @Test func aProviderReportedCostIsActualEvenForAModelNobodyCanPrice() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        await pipelines.store.apply(
            .workerAppeared(
                StoreFixture.worker("worker-1", model: "vendor/mystery-model", provider: "openrouter")
            )
        )
        await pipelines.store.apply(
            .usage(
                ProxyUsage(
                    workerID: "worker-1",
                    provider: "openrouter",
                    modelName: "vendor/mystery-model",
                    inputTokens: 1_000,
                    outputTokens: 200,
                    cacheHitTokens: 0,
                    currentContextTokens: 1_000,
                    occurredAt: StoreFixture.date(1),
                    reportedCostUSD: 0.0042
                )
            )
        )

        let agent = try #require(agents(in: await pipelines.store.tree).first)
        #expect(agent.costSource == .providerReported)
        #expect(abs(agent.estimatedCostUSD - 0.0042) < 0.000_001)
        // The model list does not know this model, so the context meter reports no data rather
        // than drawing a small window.
        #expect(agent.maxContextWindow == 0)
    }

    @Test func aLocalPriceIsEstimated() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        await pipelines.store.apply(.sessionAppeared(StoreFixture.session()))
        await pipelines.store.apply(
            .turnAppended(StoreFixture.turn(input: 100_000, output: 10_000, cache: 0, context: 100_000, at: 1))
        )

        let agent = try #require(agents(in: await pipelines.store.tree).first)
        #expect(agent.costSource == .estimated)
        #expect(agent.estimatedCostUSD > 0)
    }

    @Test func aBalanceDropBecomesDerivedSpendForTheAgentsThatSpentIt() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "deepseek-chat", provider: "deepseek"))
        )
        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-2", model: "deepseek-chat", provider: "deepseek"))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.40, at: 0)))
        await pipelines.store.apply(
            .usage(StoreFixture.usage("worker-1", input: 3_000, output: 0, at: 1))
        )
        await pipelines.store.apply(
            .usage(StoreFixture.usage("worker-2", input: 1_000, output: 0, at: 2))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 12.20, at: 60)))

        let tree = await pipelines.store.tree
        let shares = TreeMath.costs(in: tree)
        let first = try #require(shares["worker-1"])
        let second = try #require(shares["worker-2"])

        #expect(abs(first.amount - 0.15) < 0.000_001)
        #expect(abs(second.amount - 0.05) < 0.000_001)
        #expect(first.source == .balanceDerived)
        #expect(second.source == .balanceDerived)
        // The derived figures replace the local estimates for that window instead of adding to them.
        #expect(abs(TreeMath.total(in: tree) - 0.20) < 0.000_001)
    }

    @Test func aTopUpWindowBooksNoSpendAndNeverGoesNegative() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "deepseek-chat", provider: "deepseek"))
        )
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 2.00, at: 0)))
        await pipelines.store.apply(.usage(StoreFixture.usage("worker-1", input: 3_000, output: 0, at: 1)))
        await pipelines.store.apply(BalanceUpdate.loaded(StoreFixture.balance("deepseek", amount: 22.00, at: 60)))

        let tree = await pipelines.store.tree
        let agent = try #require(agents(in: tree).first)
        #expect(agent.estimatedCostUSD >= 0)
        #expect(agent.costSource == .estimated)
        // The tokens were spent before the top-up, so the window's own figure stays. No 20 dollar
        // top-up is booked as negative spend, and no derived figure comes from it.
        #expect(agent.estimatedCostUSD > 0.0005)
        #expect(agents(in: tree).allSatisfy { $0.estimatedCostUSD < 0.01 })
    }

    @Test func aHarnessReportedTurnPriceIsBookedWithItsSourceAndFamily() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        let session = "session-pi"
        await pipelines.store.apply(
            .sessionAppeared(
                StoreFixture.session(
                    session,
                    model: "deepseek-flash",
                    provider: "deepseek",
                    harness: HarnessIdentity(kind: .piAgent, sessionID: session, transport: .jsonl)
                )
            )
        )
        // The local table does not know this model, so the only figure is the harness's own.
        await pipelines.store.apply(
            .turnAppended(
                StoreFixture.turn(
                    session,
                    model: "deepseek-flash",
                    input: 100,
                    output: 20,
                    at: 1,
                    turnHarnessReportedUSD: 0.0014
                )
            )
        )

        let agent = try #require(agents(in: await pipelines.store.tree).first)
        #expect(agent.costSource == .harnessReported)
        #expect(abs(agent.estimatedCostUSD - 0.0014) < 0.000_000_001)
        // The row is grouped by the family that bills it, and the harness keeps its own field.
        #expect(agent.provider == "deepseek")
        #expect(agent.harness?.kind == .piAgent)
    }

    @Test func aHarnessNameInTheProviderSlotNeverReachesTheRow() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        let session = "session-pi"
        // A source that names itself in the provider slot is still grouped by the account that pays.
        await pipelines.store.apply(
            .sessionAppeared(
                StoreFixture.session(
                    session,
                    model: "deepseek-flash",
                    provider: "pi",
                    harness: HarnessIdentity(kind: .piAgent, sessionID: session, transport: .jsonl)
                )
            )
        )
        await pipelines.store.apply(
            .turnAppended(
                StoreFixture.turn(
                    session,
                    model: "deepseek-flash",
                    input: 100,
                    at: 1,
                    turnHarnessReportedUSD: 0.0014
                )
            )
        )

        let agent = try #require(agents(in: await pipelines.store.tree).first)
        #expect(agent.billingAccount?.id == "deepseek")
        #expect(agent.provider == "deepseek")
        #expect(agent.harness?.kind == .piAgent)
    }

    @Test func anUnknownModelReportsCostUnavailableWithItsID() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "mystery-model", provider: "deepseek"))
        )
        await pipelines.store.apply(.usage(StoreFixture.usage("worker-1", model: "mystery-model", input: 1_000, at: 1)))

        let tree = await pipelines.store.tree
        let agent = try #require(agents(in: tree).first)

        #expect(agent.modelName == "mystery-model")
        #expect(agent.costSource == nil)
        #expect(agent.estimatedCostUSD == 0)
        #expect(agent.maxContextWindow == 0)
        // No workspace total is published from a partial figure.
        let workspace = try #require(tree.workspaces.first)
        #expect(workspace.spendFigure == nil)
        #expect(tree.spendFigure == nil)
    }

    @Test func theProvidersModelListReplacesASmallerBundledWindow() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "deepseek-chat", provider: "deepseek"))
        )
        let before = await pipelines.store.tree
        #expect(try #require(agents(in: before).first).maxContextWindow == 128_000)

        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "deepseek-chat",
                    provider: .deepseek,
                    contextWindow: 1_048_576,
                    fetchedAt: StoreFixture.referenceDate
                )
            ],
            fetchedAt: StoreFixture.referenceDate
        )
        await pipelines.store.updateCatalog(catalog)

        let after = await pipelines.store.tree
        #expect(try #require(agents(in: after).first).maxContextWindow == 1_048_576)
    }

    @Test func aModelThatBecomesKnownIsPricedFromTheModelList() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let pipelines = StoreFixture.pipelines(clock: clock)
        await pipelines.store.apply(
            .workerAppeared(StoreFixture.worker("worker-1", model: "vendor-new-model", provider: "deepseek"))
        )
        await pipelines.store.apply(
            .usage(StoreFixture.usage("worker-1", model: "vendor-new-model", input: 1_000, at: 1))
        )
        #expect(try #require(agents(in: await pipelines.store.tree).first).costSource == nil)

        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "vendor-new-model",
                    provider: .deepseek,
                    contextWindow: 300_000,
                    inputPerMillion: 1.00,
                    outputPerMillion: 2.00,
                    fetchedAt: StoreFixture.referenceDate
                )
            ],
            fetchedAt: StoreFixture.referenceDate
        )
        await pipelines.store.updateCatalog(catalog)

        let agent = try #require(agents(in: await pipelines.store.tree).first)
        #expect(agent.costSource == .estimated)
        #expect(abs(agent.estimatedCostUSD - 0.001) < 0.000_001)
        #expect(agent.maxContextWindow == 300_000)
    }

    @Test func aSnapshotCarriesNoCredentialField() throws {
        // The snapshot is the only thing the widget reads and the only file written outside the
        // app. Its schema has no place for a key, and this keeps it that way.
        let data = try JSONEncoder().encode(SurgeFixtures.snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == ["schemaVersion", "generatedAt", "workspaces", "balances", "dailySpend"])
        let balances = try #require(object["balances"] as? [[String: Any]])
        let allowed: Set<String> = ["provider", "amountUSD", "lastPolledAt", "kind", "usageUSD"]
        for balance in balances {
            #expect(Set(balance.keys).isSubset(of: allowed))
        }
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("sk-") == false)
    }
}

private enum TreeMath {
    static func costs(in tree: StoreTree) -> [String: (amount: Double, source: CostSource?)] {
        var costs: [String: (amount: Double, source: CostSource?)] = [:]
        for workspace in tree.workspaces {
            for agent in [workspace.orchestrator] + workspace.workers {
                costs[agent.id] = (agent.estimatedCostUSD, agent.costSource)
            }
        }
        return costs
    }

    static func total(in tree: StoreTree) -> Double {
        tree.workspaces.reduce(0) { $0 + $1.totalTreeCostUSD }
    }
}
