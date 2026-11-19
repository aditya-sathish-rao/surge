import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

@MainActor
struct ObservationTests {
    @Test func modelKeepsRowIdentityWhileContentChanges() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        let model = SurgeStoreModel(store: harness.store)

        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        model.apply(await harness.store.tree)
        let firstRow = try #require(model.workspaces.first)
        #expect(firstRow.attentionCount == 0)

        await harness.store.record(.waitingForYou, for: "session-a", at: StoreFixture.date(10))
        model.apply(await harness.store.tree)
        let updatedRow = try #require(model.workspaces.first)

        #expect(updatedRow === firstRow)
        #expect(updatedRow.attentionCount == 1)
        #expect(updatedRow.workspace.orchestrator.status == .waitingForYou)
        #expect(model.attentionCount == 1)
    }

    @Test func modelKeepsOtherRowsStillWhenOneWorkspaceChanges() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        let model = SurgeStoreModel(store: harness.store)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-alpha", path: "/code/alpha")))
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-beta", path: "/code/beta")))
        model.apply(await harness.store.tree)

        let alphaRow = try #require(model.workspaces.first { $0.workspace.projectPath == "/code/alpha" })
        let betaRow = try #require(model.workspaces.first { $0.workspace.projectPath == "/code/beta" })
        let alphaBefore = alphaRow.workspace

        await harness.store.apply(.turnAppended(StoreFixture.turn("session-beta", output: 1_000, at: 10)))
        model.apply(await harness.store.tree)

        let alphaAfter = try #require(model.workspaces.first { $0.workspace.projectPath == "/code/alpha" })
        let betaAfter = try #require(model.workspaces.first { $0.workspace.projectPath == "/code/beta" })
        #expect(alphaAfter === alphaRow)
        #expect(betaAfter === betaRow)
        #expect(alphaAfter.workspace == alphaBefore)
        #expect(betaAfter.workspace.orchestrator.outputTokens == 1_000)
        #expect(model.orchestratorCount == 2)
    }

    @Test func modelDropsAnExpiredDoneWorkspace() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        let model = SurgeStoreModel(store: harness.store)

        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-alpha", path: "/code/alpha")))
        await harness.store.apply(.sessionAppeared(StoreFixture.session("session-beta", path: "/code/beta")))
        await harness.store.apply(.sessionEnded(sessionID: "session-beta", occurredAt: StoreFixture.date(60)))
        model.apply(await harness.store.tree)
        #expect(model.workspaces.count == 2)

        clock.advance(661)
        await harness.store.apply(.turnAppended(StoreFixture.turn("session-alpha", output: 10, at: 660)))
        await harness.store.refresh()
        model.apply(await harness.store.tree)

        #expect(model.workspaces.map(\.workspace.projectPath) == ["/code/alpha"])
        #expect(model.attentionCount == 0)
    }

    @Test func modelMirrorsBalancesAndSpend() async throws {
        let clock = TestClock(StoreFixture.referenceDate)
        let harness = StoreFixture.pipelines(clock: clock)
        let model = SurgeStoreModel(store: harness.store)

        await harness.store.apply(.sessionAppeared(StoreFixture.session(at: 0)))
        await harness.store.apply(.turnAppended(StoreFixture.turn(output: 20_000, at: 10)))
        await harness.store.apply(.loaded(StoreFixture.balance(amount: 12.40)))
        model.apply(await harness.store.tree)

        #expect(model.balances.map(\.provider) == ["deepseek"])
        #expect(abs(model.totalSpendUSD - 0.30) < 0.000_001)
        #expect(model.generatedAt != nil)
    }
}
