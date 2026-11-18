import Foundation
import SurgeCore
import Testing

@testable import SurgeUI

struct NavigationTextTests {
    @Test func tabsCarryTheirPositionAndTitle() {
        #expect(SurgeTab.allCases.map(\.title) == ["Agents", "Usage", "Spend"])
        #expect(SurgeTab.agents.position == 1)
        #expect(SurgeTab.usage.position == 2)
        #expect(SurgeTab.spend.position == 3)
        #expect(SurgeTab.agents.accessibilityLabel == "Agents, tab, 1 of 3")
        #expect(SurgeTab.usage.accessibilityLabel == "Usage, tab, 2 of 3")
        #expect(SurgeTab.spend.accessibilityLabel == "Spend, tab, 3 of 3")
    }

    @Test func chipsCountAgentsAndSubAgents() {
        let chips = WorkspaceChip.make(for: SurgeFixtures.workspaces)

        #expect(chips.map(\.title) == ["All", "surge-widget", "docs-site", "surge-proxy"])
        #expect(chips.map(\.agentCount) == [7, 3, 2, 2])
        #expect(chips.map(\.titleWithCount) == ["All 7", "surge-widget 3", "docs-site 2", "surge-proxy 2"])
        #expect(chips[1].countText == "3 agents")
        #expect(chips[1].accessibilityLabel == "surge-widget, 3 agents")
        #expect(chips[0].accessibilityLabel == "All, 7 agents")
    }

    @Test func oneAgentReadsAsSingular() {
        #expect(WorkspaceChip(filter: .all, title: "All", agentCount: 1).countText == "1 agent")
    }

    @Test func chipsFollowTheWorkspaceOrderAndKeepTheirIdentity() {
        let chips = WorkspaceChip.make(for: SurgeFixtures.workspaces)

        #expect(chips[0].filter == .all)
        #expect(chips[1].filter == .workspace(SurgeFixtures.workspaces[0].id))
        #expect(chips[1].id == SurgeFixtures.workspaces[0].id.uuidString)
        #expect(chips[0].id == "all")
    }

    @Test func noWorkspacesStillShowsTheAllChip() {
        let chips = WorkspaceChip.make(for: [])

        #expect(chips.count == 1)
        #expect(chips[0].titleWithCount == "All 0")
        #expect(chips[0].accessibilityLabel == "All, 0 agents")
    }

    @Test func emptyStateCopyPointsAtTheNextStep() {
        #expect(SurgeEmptyState.prompt == "> no agents running_")
        #expect(SurgeEmptyState.title == "No agents running")
        #expect(SurgeEmptyState.detail == "Start Claude Code, or point workers at 127.0.0.1:8899.")
        #expect(
            SurgeEmptyState.accessibilityLabel
                == "No agents running. Start Claude Code, or point workers at 127.0.0.1:8899."
        )
    }
}
