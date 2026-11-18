import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

struct MergeTests {
    @Test func mergedTreeDoesNotDependOnPipelineOrder() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let first = StoreFixture.pipelines(clock: clock)
        let second = StoreFixture.pipelines(clock: clock)

        let tailerEvents: [TailerEvent] = [
            .sessionAppeared(StoreFixture.session(at: 0)),
            .turnAppended(
                StoreFixture.turn(input: 1_000, output: 200, cache: 500, context: 6_000, at: 10)
            ),
        ]
        let proxyEvents: [ProxyEvent] = [
            .workerAppeared(StoreFixture.worker(at: 5)),
            .usage(
                StoreFixture.usage(input: 2_000, output: 400, cache: 1_000, context: 3_000, at: 20)
            ),
        ]
        let walletUpdates: [BalanceUpdate] = [.loaded(StoreFixture.balance(amount: 12.40))]

        for event in tailerEvents { await first.store.apply(event) }
        for event in proxyEvents { await first.store.apply(event) }
        for update in walletUpdates { await first.store.apply(update) }

        for update in walletUpdates { await second.store.apply(update) }
        for event in proxyEvents { await second.store.apply(event) }
        for event in tailerEvents { await second.store.apply(event) }

        let lhs = await first.store.tree
        let rhs = await second.store.tree

        #expect(lhs.workspaces == rhs.workspaces)
        #expect(lhs.balances == rhs.balances)
        #expect(lhs.workspaces.count == 1)
        #expect(lhs.workspaces.first?.orchestrator.id == "session-a")
        #expect(lhs.workspaces.first?.workers.map(\.id) == ["worker-1"])
    }

    @Test func concurrentPipelinesMergeIntoOneTree() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let reference = StoreFixture.pipelines(clock: clock)

        let tailerEvents: [TailerEvent] = [
            .sessionAppeared(StoreFixture.session(at: 0)),
            .turnAppended(
                StoreFixture.turn(input: 1_000, output: 200, cache: 500, context: 6_000, at: 10)
            ),
        ]
        let proxyEvents: [ProxyEvent] = [
            .workerAppeared(StoreFixture.worker(at: 5)),
            .usage(
                StoreFixture.usage(input: 2_000, output: 400, cache: 1_000, context: 3_000, at: 20)
            ),
        ]
        let walletUpdates: [BalanceUpdate] = [.loaded(StoreFixture.balance(amount: 12.40))]

        for event in tailerEvents { await reference.store.apply(event) }
        for event in proxyEvents { await reference.store.apply(event) }
        for update in walletUpdates { await reference.store.apply(update) }

        let concurrent = StoreFixture.pipelines(clock: clock)
        let store = concurrent.store
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for event in tailerEvents { await store.apply(event) }
            }
            group.addTask {
                for event in proxyEvents { await store.apply(event) }
            }
            group.addTask {
                for update in walletUpdates { await store.apply(update) }
            }
        }

        let expected = await reference.store.tree
        let merged = await store.tree
        #expect(merged.workspaces == expected.workspaces)
        #expect(merged.balances == expected.balances)
    }

    @Test func anOlderTurnDoesNotReviveADoneSession() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn(output: 1_000, context: 9_000, at: 100))
        )
        await harness.store.apply(.sessionEnded(sessionID: "session-a", occurredAt: StoreFixture.date(120)))
        await harness.store.apply(
            .turnAppended(StoreFixture.turn(output: 500, context: 2_000, at: 50))
        )

        let tree = await harness.store.tree
        let orchestrator = tree.workspaces.first?.orchestrator
        #expect(orchestrator?.status == .done)
        #expect(orchestrator?.currentContextTokens == 9_000)
        #expect(orchestrator?.outputTokens == 1_500)
    }

    @Test func peerSessionsShareOneWorkspaceAndKeepTheirOwnSubAgents() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-a", at: 0)))
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-b", at: 10)))
        await harness.store.apply(
            .workerAppeared(StoreFixture.worker("worker-b", parent: "session-b", at: 20))
        )

        let tree = await harness.store.tree
        #expect(tree.workspaces.count == 1)
        let workspace = tree.workspaces.first
        #expect(workspace?.orchestrator.id == "session-b")
        #expect(workspace?.workers.map(\.id) == ["worker-b", "session-a"])
    }

    @Test func aWorkerNestsUnderThePeerThatNamedIt() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-a", at: 0)))
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-b", at: 5)))
        await harness.store.apply(.turnAppended(StoreFixture.turn("session-a", output: 10, at: 20)))
        await harness.store.apply(
            .workerAppeared(StoreFixture.worker("worker-b", parent: "session-b", at: 10))
        )

        let tree = await harness.store.tree
        let workspace = tree.workspaces.first
        #expect(workspace?.orchestrator.id == "session-b")
        #expect(workspace?.workers.map(\.id) == ["worker-b", "session-a"])
    }

    @Test func ambiguousWorkerParentsFallBackToTheMostRecentSession() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-a", at: 0)))
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-b", at: 5)))
        await harness.store.apply(
            .workerAppeared(StoreFixture.worker("worker-a", parent: "session-a", at: 10))
        )
        await harness.store.apply(
            .workerAppeared(StoreFixture.worker("worker-b", parent: "session-b", at: 11))
        )

        let tree = await harness.store.tree
        let workspace = tree.workspaces.first
        #expect(workspace?.orchestrator.id == "session-b")
        #expect(workspace?.workers.map(\.id) == ["worker-b", "session-a", "worker-a"])
    }

    @Test func eventsForAnUnknownAgentAreIgnored() async {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)

        await harness.store.apply(.turnAppended(StoreFixture.turn(at: 0)))
        await harness.store.apply(.usage(StoreFixture.usage(at: 0)))
        await harness.store.apply(.sessionEnded(sessionID: "session-a", occurredAt: StoreFixture.date(0)))

        let tree = await harness.store.tree
        #expect(tree.workspaces.isEmpty)
        #expect(tree.balances.isEmpty)
    }
}
