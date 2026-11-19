import Foundation
import SurgeCore
import Testing

@testable import SurgeWidgetLogic

/// Sample data built from `SurgeCore`'s fixtures so the widget never invents its own numbers.
enum WidgetTestFixtures {
    static let now = SurgeFixtures.referenceDate
    static let snapshot = SurgeFixtures.snapshot

    static var widgetWorkspace: WorkspaceSession { SurgeFixtures.workspaces[0] }
    static var docsWorkspace: WorkspaceSession { SurgeFixtures.workspaces[1] }
    static var proxyWorkspace: WorkspaceSession { SurgeFixtures.workspaces[2] }

    static func agent(
        id: String = "agent",
        provider: String = "anthropic",
        model: String = "claude-sonnet",
        status: AgentStatus = .working,
        contextTokens: Int = 50_000,
        window: Int = 200_000,
        costUSD: Double = 0.10,
        lastTokenAt: Date = now
    ) -> AgentNode {
        AgentNode(
            id: id,
            provider: provider,
            modelName: model,
            status: status,
            currentContextTokens: contextTokens,
            maxContextWindow: window,
            estimatedCostUSD: costUSD,
            lastTokenAt: lastTokenAt
        )
    }

    static func workspace(
        id: UUID = UUID(),
        path: String = "/Users/dev/github/example",
        orchestrator: AgentNode = agent(),
        workers: [AgentNode] = []
    ) -> WorkspaceSession {
        WorkspaceSession(id: id, projectPath: path, orchestrator: orchestrator, workers: workers)
    }

    static func snapshot(
        workspaces: [WorkspaceSession],
        generatedAt: Date = now,
        balances: [AccountBalance] = [],
        dailySpend: [DailySpendPoint] = [],
        schemaVersion: Int = SurgeSnapshot.currentSchemaVersion
    ) -> SurgeSnapshot {
        SurgeSnapshot(
            generatedAt: generatedAt,
            workspaces: workspaces,
            balances: balances,
            dailySpend: dailySpend,
            schemaVersion: schemaVersion
        )
    }

    /// Every agent working, so the Small widget takes its calm branch.
    static var calmSnapshot: SurgeSnapshot {
        snapshot(workspaces: [
            workspace(
                path: "/Users/dev/github/surge-widget",
                orchestrator: agent(id: "orch", status: .working),
                workers: [
                    agent(id: "worker-a", provider: "deepseek", model: "deepseek-chat", status: .working),
                    agent(id: "worker-b", provider: "deepseek", model: "deepseek-reasoner", status: .working),
                ]
            )
        ])
    }
}
