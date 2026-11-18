import Foundation
import SurgeCore
import Testing

struct FixturesTests {
    @Test func sampleSnapshotCoversEveryStatusAcrossMultipleWorkspaces() {
        let snapshot = SurgeFixtures.snapshot
        let agents = snapshot.workspaces.flatMap { [$0.orchestrator] + $0.workers }
        let statusKinds = Set(agents.map { statusKind($0.status) })

        #expect(snapshot.workspaces.count >= 2)
        #expect(
            statusKinds == [
                "working", "waitingForYou", "stalled", "compacting", "idle", "done", "noSignal",
            ]
        )
        #expect(agents.filter { $0.status.needsYou }.count == 2)
    }

    @Test func sampleSnapshotHasSevenDaysOfSpendAndBalances() {
        let snapshot = SurgeFixtures.snapshot

        #expect(snapshot.dailySpend.count == 7)
        #expect(snapshot.dailySpend.last?.date == SurgeFixtures.referenceDate)
        #expect(snapshot.dailySpend.allSatisfy { $0.totalUSD > 0 })

        #expect(snapshot.balances.count == 3)
        #expect(snapshot.balances.contains { $0.isAvailable == false })
        #expect(snapshot.balances.contains { $0.level == .low })
    }

    @Test func workspacesNeedingYouSortFirst() {
        let workspaces = SurgeFixtures.workspaces

        #expect(workspaces.first?.needsYou == true)
        #expect(workspaces.dropFirst().allSatisfy { $0.needsYou == false })
    }

    @Test func emptySnapshotIsEmptyButVersioned() {
        let snapshot = SurgeFixtures.emptySnapshot

        #expect(snapshot.workspaces.isEmpty)
        #expect(snapshot.balances.isEmpty)
        #expect(snapshot.dailySpend.isEmpty)
        #expect(snapshot.schemaVersion == SurgeSnapshot.currentSchemaVersion)
    }

    private func statusKind(_ status: AgentStatus) -> String {
        switch status {
        case .working: "working"
        case .waitingForYou: "waitingForYou"
        case .stalled: "stalled"
        case .compacting: "compacting"
        case .idle: "idle"
        case .done: "done"
        case .noSignal: "noSignal"
        }
    }
}
