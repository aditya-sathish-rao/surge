import Foundation

public enum SurgeFixtures {
    public static let referenceDate = Date(timeIntervalSince1970: 1_763_000_000)

    public static var snapshot: SurgeSnapshot {
        SurgeSnapshot(
            generatedAt: referenceDate,
            workspaces: workspaces,
            balances: balances,
            dailySpend: dailySpend
        )
    }

    public static var emptySnapshot: SurgeSnapshot {
        SurgeSnapshot(
            generatedAt: referenceDate,
            workspaces: [],
            balances: [],
            dailySpend: []
        )
    }

    public static var workspaces: [WorkspaceSession] {
        [widgetWorkspace, docsWorkspace, proxyWorkspace]
    }

    public static var balances: [AccountBalance] {
        [
            AccountBalance(provider: "anthropic", amountUSD: nil, lastPolledAt: referenceDate),
            AccountBalance(provider: "deepseek", amountUSD: 12.40, lastPolledAt: referenceDate),
            AccountBalance(provider: "openrouter", amountUSD: 3.20, lastPolledAt: referenceDate),
        ]
    }

    public static var dailySpend: [DailySpendPoint] {
        let series: [[String: Double]] = [
            ["anthropic": 0.42, "deepseek": 0.18, "openrouter": 0.05],
            ["anthropic": 0.71, "deepseek": 0.24, "openrouter": 0.09],
            ["anthropic": 0.35, "deepseek": 0.12, "openrouter": 0.00],
            ["anthropic": 0.88, "deepseek": 0.31, "openrouter": 0.12],
            ["anthropic": 0.54, "deepseek": 0.19, "openrouter": 0.07],
            ["anthropic": 1.02, "deepseek": 0.42, "openrouter": 0.15],
            ["anthropic": 0.83, "deepseek": 0.28, "openrouter": 0.11],
        ]
        return series.enumerated().map { index, spend in
            let daysAgo = Double(series.count - 1 - index)
            return DailySpendPoint(
                date: referenceDate.addingTimeInterval(-daysAgo * 86_400),
                spendByProvider: spend
            )
        }
    }

    public static func pricingTable() throws -> PricingTable {
        try PricingTable.bundled()
    }

    private static let widgetWorkspace = WorkspaceSession(
        id: makeUUID("11111111-1111-4111-8111-111111111111"),
        projectPath: "/Users/dev/github/surge-widget",
        orchestrator: AgentNode(
            id: "session-widget-claude",
            provider: "anthropic",
            modelName: "claude-sonnet",
            status: .working,
            inputTokens: 42_000,
            outputTokens: 8_800,
            cacheHitTokens: 152_000,
            currentContextTokens: 102_000,
            maxContextWindow: 200_000,
            estimatedCostUSD: 0.30,
            lastTokenAt: referenceDate.addingTimeInterval(-8)
        ),
        workers: [
            AgentNode(
                id: "worker-widget-reasoner",
                provider: "deepseek",
                modelName: "deepseek-reasoner",
                status: .stalled(since: referenceDate.addingTimeInterval(-380)),
                inputTokens: 18_000,
                outputTokens: 6_200,
                cacheHitTokens: 44_000,
                currentContextTokens: 96_000,
                maxContextWindow: 128_000,
                estimatedCostUSD: 0.21,
                lastTokenAt: referenceDate.addingTimeInterval(-380)
            ),
            AgentNode(
                id: "worker-widget-chat",
                provider: "deepseek",
                modelName: "deepseek-chat",
                status: .waitingForYou,
                inputTokens: 9_000,
                outputTokens: 2_400,
                cacheHitTokens: 12_000,
                currentContextTokens: 32_000,
                maxContextWindow: 128_000,
                estimatedCostUSD: 0.04,
                lastTokenAt: referenceDate.addingTimeInterval(-45)
            ),
        ]
    )

    private static let docsWorkspace = WorkspaceSession(
        id: makeUUID("22222222-2222-4222-8222-222222222222"),
        projectPath: "/Users/dev/github/docs-site",
        orchestrator: AgentNode(
            id: "session-docs-claude",
            provider: "anthropic",
            modelName: "claude-sonnet",
            status: .done,
            inputTokens: 121_000,
            outputTokens: 26_000,
            cacheHitTokens: 210_000,
            currentContextTokens: 148_000,
            maxContextWindow: 200_000,
            estimatedCostUSD: 1.04,
            lastTokenAt: referenceDate.addingTimeInterval(-2_520)
        ),
        workers: [
            AgentNode(
                id: "worker-docs-openrouter",
                provider: "openrouter",
                modelName: "openrouter-auto",
                status: .noSignal,
                currentContextTokens: 0,
                maxContextWindow: 0,
                estimatedCostUSD: 0,
                lastTokenAt: referenceDate.addingTimeInterval(-3_600)
            )
        ]
    )

    private static let proxyWorkspace = WorkspaceSession(
        id: makeUUID("33333333-3333-4333-8333-333333333333"),
        projectPath: "/Users/dev/github/surge-proxy",
        orchestrator: AgentNode(
            id: "session-proxy-claude",
            provider: "anthropic",
            modelName: "claude-sonnet",
            status: .compacting,
            inputTokens: 96_000,
            outputTokens: 21_000,
            cacheHitTokens: 188_000,
            currentContextTokens: 181_000,
            maxContextWindow: 200_000,
            estimatedCostUSD: 0.91,
            lastTokenAt: referenceDate.addingTimeInterval(-32)
        ),
        workers: [
            AgentNode(
                id: "worker-proxy-chat",
                provider: "deepseek",
                modelName: "deepseek-chat",
                status: .idle(since: referenceDate.addingTimeInterval(-420)),
                inputTokens: 7_000,
                outputTokens: 1_800,
                cacheHitTokens: 9_000,
                currentContextTokens: 12_000,
                maxContextWindow: 128_000,
                estimatedCostUSD: 0.03,
                lastTokenAt: referenceDate.addingTimeInterval(-420)
            )
        ]
    )

    private static func makeUUID(_ value: String) -> UUID {
        UUID(uuidString: value) ?? UUID()
    }
}
