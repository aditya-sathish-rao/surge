import Foundation
import SurgeCore
import Testing

@testable import SurgeWidgetLogic

struct WidgetContentTests {
    @Test func theSmallWidgetShowsTheAgentThatNeedsYouBeforeTheWorkingCount() {
        let content = WidgetSmallContent(snapshot: WidgetTestFixtures.snapshot, filter: .all)

        guard case .needsYou(let agent, let others) = content else {
            Issue.record("Expected the needs-you state, got \(content)")
            return
        }
        #expect(agent.agent.id == "worker-widget-chat")
        #expect(agent.workspaceName == "surge-widget")
        #expect(others == 1)
    }

    @Test func theSmallWidgetCountsWorkingAgentsWhenNothingNeedsYou() {
        let content = WidgetSmallContent(snapshot: WidgetTestFixtures.calmSnapshot, filter: .all)

        guard case .calm(let working, let workspaceCount, let fuseAgents) = content else {
            Issue.record("Expected the calm state, got \(content)")
            return
        }
        #expect(working == 3)
        #expect(workspaceCount == 1)
        #expect(fuseAgents.count == 3)
    }

    @Test func theSmallWidgetNeverDrawsMoreThanFourFuses() {
        let workers = (1...6).map { WidgetTestFixtures.agent(id: "worker-\($0)") }
        let snapshot = WidgetTestFixtures.snapshot(workspaces: [WidgetTestFixtures.workspace(workers: workers)])

        let content = WidgetSmallContent(snapshot: snapshot, filter: .all)

        guard case .calm(_, _, let fuseAgents) = content else {
            Issue.record("Expected the calm state, got \(content)")
            return
        }
        #expect(fuseAgents.count == WidgetSmallContent.fuseAgentCount)
    }

    @Test func anEmptySnapshotHasNoAgentsToShow() {
        #expect(WidgetSmallContent(snapshot: SurgeFixtures.emptySnapshot, filter: .all) == .noAgents)
    }

    @Test func aWorkspaceFilterLimitsTheSmallWidgetToThatProject() {
        let content = WidgetSmallContent(
            snapshot: WidgetTestFixtures.snapshot,
            filter: .workspace(WidgetTestFixtures.widgetWorkspace.id)
        )

        guard case .needsYou(let agent, let others) = content else {
            Issue.record("Expected the needs-you state, got \(content)")
            return
        }
        #expect(agent.workspaceID == WidgetTestFixtures.widgetWorkspace.id)
        #expect(others == 1)
    }

    @Test func aFreshSnapshotShowsNoCaption() {
        let generatedAt = WidgetTestFixtures.now

        #expect(WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt) == nil)
        #expect(WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(299)) == nil)
        #expect(WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(300)) == nil)
    }

    @Test func aStaleSnapshotSaysHowOldItIs() {
        let generatedAt = WidgetTestFixtures.now

        #expect(
            WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(301))
                == "Updated 5 min ago"
        )
        #expect(
            WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(120))
                == nil
        )
        #expect(
            WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(3600))
                == "Updated 1h ago"
        )
        #expect(
            WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(5450))
                == "Updated 1h 30m ago"
        )
        #expect(
            WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(2 * 86_400))
                == "Updated 2d ago"
        )
    }

    @Test func aSnapshotFromTheFutureNeverClaimsToBeStale() {
        let generatedAt = WidgetTestFixtures.now

        #expect(WidgetFreshness.caption(generatedAt: generatedAt, now: generatedAt.addingTimeInterval(-600)) == nil)
    }

    @Test func theHeaderSaysWhatNeedsYou() {
        #expect(WidgetHeader.attention(needing: 0) == "All agents working")
        #expect(WidgetHeader.attention(needing: 1) == "1 needs you")
        #expect(WidgetHeader.attention(needing: 2) == "2 need you")
        #expect(WidgetHeader.othersNeeding(1) == "+1 more needs you")
        #expect(WidgetHeader.othersNeeding(3) == "+3 more need you")
        #expect(WidgetHeader.overflow(1) == "+1 more agent")
        #expect(WidgetHeader.overflow(4) == "+4 more agents")
        #expect(WidgetHeader.agentCount(1) == "1 agent")
        #expect(WidgetHeader.agentCount(4) == "4 agents")
    }

    @Test func theSmallWidgetSubtitleSaysWhatIsWorking() {
        #expect(WidgetHeader.calmSubtitle(working: 4, workspaceCount: 2) == "working · 2 workspaces")
        #expect(WidgetHeader.calmSubtitle(working: 1, workspaceCount: 1) == "working · 1 workspace")
        #expect(WidgetHeader.calmSubtitle(working: 0, workspaceCount: 0) == "nothing working")
    }

    @Test func aRowFitsTheShortStateWordNotTheSentence() {
        #expect(WidgetStatusWording.short(.working) == "Working")
        #expect(WidgetStatusWording.short(.waitingForYou) == "Waiting")
        #expect(WidgetStatusWording.short(.stalled(since: WidgetTestFixtures.now)) == "Stalled")
        #expect(WidgetStatusWording.short(.idle(since: WidgetTestFixtures.now)) == "Idle")
        #expect(WidgetStatusWording.short(.compacting) == "Compacting")
        #expect(WidgetStatusWording.short(.done) == "Done")
        #expect(WidgetStatusWording.short(.noSignal) == "No signal")
    }

    @Test func theFooterShowsAccountsThatReportABalanceFirst() {
        let balances = [
            AccountBalance(provider: "anthropic", amountUSD: nil, lastPolledAt: WidgetTestFixtures.now),
            AccountBalance(provider: "deepseek", amountUSD: 12.40, lastPolledAt: WidgetTestFixtures.now),
            AccountBalance(provider: "openrouter", amountUSD: 3.20, lastPolledAt: WidgetTestFixtures.now),
        ]

        let visible = WidgetBalances.visible(balances, limit: 2)

        #expect(visible.map(\.provider) == ["deepseek", "openrouter"])
    }

    @Test func anAccountWithoutABalanceStillSaysSoWhenItIsAllThereIs() {
        let balances = [
            AccountBalance(provider: "anthropic", amountUSD: nil, lastPolledAt: WidgetTestFixtures.now)
        ]

        let visible = WidgetBalances.visible(balances, limit: 2)

        #expect(visible.map(\.provider) == ["anthropic"])
        #expect(visible.first?.isAvailable == false)
    }

    @Test func theTitleNamesTheWorkspaceOrSaysAll() {
        #expect(WidgetHeader.title(workspaceName: "surge-widget") == "Surge · surge-widget")
        #expect(WidgetHeader.title(workspaceName: nil) == "Surge · all workspaces")
    }

    @Test func aClickOpensThePanelAtTheRelevantPlace() {
        #expect(WidgetDeepLink.panelURL(workspaceID: nil).absoluteString == "surge://panel")
        #expect(
            WidgetDeepLink.panelURL(workspaceID: WidgetTestFixtures.widgetWorkspace.id).absoluteString
                == "surge://panel?workspace=\(WidgetTestFixtures.widgetWorkspace.id.uuidString)"
        )
    }

    @Test func theClickTargetFollowsTheLayoutAndTheFilter() {
        let snapshot = WidgetTestFixtures.snapshot
        let projectID = WidgetTestFixtures.widgetWorkspace.id

        #expect(WidgetDeepLink.targetWorkspace(in: snapshot, filter: .all, layout: .large) == projectID)
        #expect(WidgetDeepLink.targetWorkspace(in: snapshot, filter: .all, layout: .medium) == projectID)
        #expect(WidgetDeepLink.targetWorkspace(in: snapshot, filter: .all, layout: .small) == projectID)
        #expect(
            WidgetDeepLink.targetWorkspace(
                in: WidgetTestFixtures.calmSnapshot,
                filter: .all,
                layout: .small
            ) == nil
        )
        #expect(
            WidgetDeepLink.targetWorkspace(
                in: snapshot,
                filter: .workspace(WidgetTestFixtures.docsWorkspace.id),
                layout: .large
            ) == WidgetTestFixtures.docsWorkspace.id
        )
    }
}
