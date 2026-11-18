import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

struct PipelineTests {
    @Test(.timeLimit(.minutes(1)))
    func startConsumesEveryPipelineStream() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        await harness.store.start()

        harness.tailer.continuation.yield(.sessionAppeared(StoreFixture.session(at: 0)))
        harness.tailer.continuation.yield(
            .turnAppended(StoreFixture.turn(output: 1_000, context: 5_000, at: 10))
        )
        harness.proxy.continuation.yield(.workerAppeared(StoreFixture.worker(at: 5)))
        harness.proxy.continuation.yield(
            .usage(StoreFixture.usage(output: 500, context: 2_000, at: 20))
        )
        harness.wallets.continuation.yield(.loaded(StoreFixture.balance(amount: 12.40)))

        harness.tailer.continuation.finish()
        harness.proxy.continuation.finish()
        harness.wallets.continuation.finish()

        let tree = try #require(
            await firstTree(from: harness.store) { tree in
                guard let workspace = tree.workspaces.first, workspace.workers.count == 1 else {
                    return false
                }
                return workspace.orchestrator.outputTokens == 1_000
                    && workspace.workers[0].outputTokens == 500
                    && tree.balances.count == 1
            }
        )
        #expect(tree.workspaces[0].orchestrator.outputTokens == 1_000)
        #expect(tree.workspaces[0].workers[0].outputTokens == 500)
        #expect(tree.balances[0].amountUSD == 12.40)
        await harness.store.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func changesPublishOnlyWhenTheContentChanges() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        let changes = await harness.store.changes()

        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.refresh()
        await harness.store.refresh()

        var received: [StoreTree] = []
        for await tree in changes {
            received.append(tree)
            if received.count == 2 { break }
        }
        #expect(received[0].workspaces.isEmpty)
        #expect(received[1].workspaces.count == 1)
    }
}
