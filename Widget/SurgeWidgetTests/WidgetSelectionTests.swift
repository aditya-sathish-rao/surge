import Foundation
import SurgeCore
import Testing

@testable import SurgeWidgetLogic

struct WidgetSelectionTests {
    @Test func fourMostUrgentAgentsComeFromEverythingNeedingYouFirst() {
        let agents = WidgetSelection.urgentAgents(in: WidgetTestFixtures.snapshot, filter: .all, limit: 4)

        #expect(
            agents.map(\.agent.id) == [
                "worker-widget-chat",
                "worker-widget-reasoner",
                "session-widget-claude",
                "session-proxy-claude",
            ])
        #expect(agents.first?.needsYou == true)
    }

    @Test func aWorkspaceFilterLeavesOnlyThatProjectsAgents() {
        let agents = WidgetSelection.urgentAgents(
            in: WidgetTestFixtures.snapshot,
            filter: .workspace(WidgetTestFixtures.widgetWorkspace.id)
        )

        #expect(agents.count == 3)
        #expect(agents.allSatisfy { $0.workspaceID == WidgetTestFixtures.widgetWorkspace.id })
        #expect(agents.allSatisfy { $0.workspaceName == "surge-widget" })
    }

    @Test func aFilteredWorkspaceThatIsNoLongerThereShowsNoAgents() {
        let agents = WidgetSelection.urgentAgents(in: WidgetTestFixtures.snapshot, filter: .workspace(UUID()))

        #expect(agents.isEmpty)
    }

    @Test func workspacesNeedingYouSortFirstThenBySpend() {
        let ordered = WidgetSelection.orderedWorkspaces(WidgetTestFixtures.snapshot.workspaces)

        #expect(ordered.map(\.name) == ["surge-widget", "docs-site", "surge-proxy"])
    }

    @Test func theLargeLayoutFocusesTheWorkspaceWithTheMostAgentsNeedingYou() {
        let focused = WidgetSelection.focusedWorkspace(in: WidgetTestFixtures.snapshot)

        #expect(focused?.id == WidgetTestFixtures.widgetWorkspace.id)
    }

    @Test func anEqualNumberOfAgentsNeedingYouBreaksOnSpend() {
        let cheap = WidgetTestFixtures.workspace(
            path: "/Users/dev/github/cheap",
            orchestrator: WidgetTestFixtures.agent(id: "cheap-orch", status: .waitingForYou, costUSD: 0.20)
        )
        let expensive = WidgetTestFixtures.workspace(
            path: "/Users/dev/github/expensive",
            orchestrator: WidgetTestFixtures.agent(
                id: "expensive-orch",
                status: .stalled(since: WidgetTestFixtures.now),
                costUSD: 2.40
            )
        )

        let focused = WidgetSelection.focusedWorkspace(
            in: WidgetTestFixtures.snapshot(workspaces: [cheap, expensive])
        )

        #expect(focused?.id == expensive.id)
    }

    @Test func theTreePutsTheOrchestratorFirstAndItsMostUrgentWorkerNext() {
        let tree = WidgetSelection.tree(in: WidgetTestFixtures.widgetWorkspace)

        #expect(
            tree.map(\.agent.id) == [
                "session-widget-claude",
                "worker-widget-chat",
                "worker-widget-reasoner",
            ])
        #expect(tree.first?.isSubAgent == false)
        #expect(tree.dropFirst().allSatisfy { $0.isSubAgent })
    }

    @Test func aLongTreeIsTrimmedWithACountInsteadOfBeingCutSilently() {
        let workers = (1...7).map { WidgetTestFixtures.agent(id: "worker-\($0)") }
        let workspace = WidgetTestFixtures.workspace(workers: workers)
        let rows = WidgetSelection.trimmed(WidgetSelection.tree(in: workspace), limit: 5)

        #expect(rows.visible.count == 5)
        #expect(rows.hidden == 3)
    }

    @Test func countsAddUpAcrossWorkspaces() {
        let workspaces = WidgetTestFixtures.snapshot.workspaces

        #expect(WidgetSelection.needsYouCount(in: workspaces) == 2)
        #expect(WidgetSelection.workingCount(in: workspaces) == 1)
    }

    @Test func theWidgetFilterReadsAWorkspaceIdentifierOrFallsBackToAll() {
        let id = WidgetTestFixtures.widgetWorkspace.id

        #expect(WidgetWorkspaceFilter(workspaceID: id.uuidString) == .workspace(id))
        #expect(WidgetWorkspaceFilter(workspaceID: nil) == .all)
        #expect(WidgetWorkspaceFilter(workspaceID: "not-a-uuid") == .all)
    }
}
