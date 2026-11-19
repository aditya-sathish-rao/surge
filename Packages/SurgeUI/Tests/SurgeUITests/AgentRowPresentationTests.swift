import Foundation
import SurgeCore
import Testing

@testable import SurgeUI

struct AgentRowPresentationTests {
    @Test func voiceOverReadsTheWholeRowAsOneSentence() {
        let agent = UITestFixtures.agent(contextTokens: 144_000)
        let presentation = AgentRowPresentation(
            agent: agent,
            workspaceName: "surge-widget",
            tokensPerSecond: 68.4,
            now: UITestFixtures.now
        )

        #expect(
            presentation.accessibilityLabel
                == "Claude Sonnet, agent, surge-widget, Anthropic. "
                + "Working, 68 tokens per second. Context 72 percent, high."
        )
    }

    @Test func subAgentSaysWhoItsParentIs() {
        let agent = UITestFixtures.agent(
            provider: "deepseek",
            modelName: "deepseek-reasoner",
            status: .stalled(since: UITestFixtures.now.addingTimeInterval(-194)),
            contextTokens: 82_000,
            window: 200_000
        )
        let presentation = AgentRowPresentation(
            agent: agent,
            workspaceName: "surge-widget",
            now: UITestFixtures.now,
            kind: .subAgent(parentName: "Claude Sonnet")
        )

        #expect(
            presentation.accessibilityLabel
                == "DeepSeek Reasoner, sub-agent of Claude Sonnet, surge-widget, DeepSeek. "
                + "Stalled 3m 14s. Context 41 percent."
        )
    }

    @Test func workingWithoutARateSaysJustWorking() {
        let presentation = AgentRowPresentation(
            agent: UITestFixtures.agent(),
            workspaceName: "surge-widget",
            now: UITestFixtures.now
        )

        #expect(presentation.trailingText == "Working")
        #expect(presentation.accessibilityLabel.contains("Working. Context 42 percent."))
    }

    @Test func trailingTextUsesTheStateWordAndTimer() {
        let stalled = UITestFixtures.agent(status: .stalled(since: UITestFixtures.now.addingTimeInterval(-194)))
        let waiting = UITestFixtures.agent(status: .waitingForYou)
        let idle = UITestFixtures.agent(status: .idle(since: UITestFixtures.now.addingTimeInterval(-240)))
        let done = UITestFixtures.agent(status: .done)
        let compacting = UITestFixtures.agent(status: .compacting)
        let noSignal = UITestFixtures.agent(status: .noSignal)

        #expect(
            AgentRowPresentation.trailingText(
                for: stalled.status, tokensPerSecond: nil, now: UITestFixtures.now, lastActivityAt: stalled.lastTokenAt
            ) == "Stalled 3m 14s")
        #expect(
            AgentRowPresentation.trailingText(
                for: waiting.status, tokensPerSecond: nil, now: UITestFixtures.now, lastActivityAt: waiting.lastTokenAt
            ) == "Waiting for you")
        #expect(
            AgentRowPresentation.trailingText(
                for: idle.status, tokensPerSecond: nil, now: UITestFixtures.now, lastActivityAt: idle.lastTokenAt
            ) == "Idle 4m")
        #expect(
            AgentRowPresentation.trailingText(
                for: done.status, tokensPerSecond: nil, now: UITestFixtures.now, lastActivityAt: done.lastTokenAt
            ) == "Done · 8s")
        #expect(
            AgentRowPresentation.trailingText(
                for: compacting.status, tokensPerSecond: nil, now: UITestFixtures.now,
                lastActivityAt: compacting.lastTokenAt
            ) == "Compacting")
        #expect(
            AgentRowPresentation.trailingText(
                for: noSignal.status, tokensPerSecond: nil, now: UITestFixtures.now,
                lastActivityAt: noSignal.lastTokenAt
            ) == "No signal")
    }

    @Test func workingRowTrailsTheTokenRate() {
        let presentation = AgentRowPresentation(
            agent: UITestFixtures.agent(),
            workspaceName: "surge-widget",
            tokensPerSecond: 67.6,
            now: UITestFixtures.now
        )

        #expect(presentation.trailingText == "68 tok/s")
    }

    @Test func needsYouFollowsTheStatus() {
        func presentation(_ status: AgentStatus) -> AgentRowPresentation {
            AgentRowPresentation(
                agent: UITestFixtures.agent(status: status),
                workspaceName: "surge-widget",
                now: UITestFixtures.now
            )
        }

        #expect(presentation(.working).needsYou == false)
        #expect(presentation(.compacting).needsYou == false)
        #expect(presentation(.noSignal).needsYou == false)
        #expect(presentation(.waitingForYou).needsYou)
        #expect(presentation(.stalled(since: UITestFixtures.now)).needsYou)
    }

    @Test func theStateSymbolComesFromTheStatus() {
        #expect(
            AgentRowPresentation(
                agent: UITestFixtures.agent(status: .waitingForYou),
                workspaceName: "surge-widget",
                now: UITestFixtures.now
            ).stateSymbol == "hand.raised.fill"
        )
    }

    @Test func modelIDsReadAsWords() {
        #expect(AgentRowPresentation.displayName(forModel: "claude-sonnet") == "Claude Sonnet")
        #expect(AgentRowPresentation.displayName(forModel: "deepseek-reasoner") == "DeepSeek Reasoner")
        #expect(AgentRowPresentation.displayName(forModel: "deepseek-chat") == "DeepSeek Chat")
        #expect(AgentRowPresentation.displayName(forModel: "openrouter-auto") == "OpenRouter Auto")
        #expect(AgentRowPresentation.displayName(forModel: "gpt-4o-mini") == "GPT 4o Mini")
        #expect(AgentRowPresentation.displayName(forModel: "some_model") == "Some Model")
        #expect(AgentRowPresentation.displayName(forModel: "v3") == "V3")
        #expect(AgentRowPresentation.displayName(forModel: "") == "")
    }

    @Test func fixtureWorkspaceNamesAreUnchanged() {
        let workspace = SurgeFixtures.workspaces[0]
        let presentation = AgentRowPresentation(
            agent: workspace.orchestrator,
            workspaceName: workspace.name,
            tokensPerSecond: 68,
            now: SurgeFixtures.referenceDate
        )

        #expect(workspace.name == "surge-widget")
        #expect(presentation.provider == .anthropic)
        #expect(presentation.modelName == "Claude Sonnet")
        #expect(presentation.fuse.label == "51%")
    }
}
