import Foundation
import SurgeCore

/// Sample data for previews and for the offscreen render checks. It is built from `SurgeCore`'s
/// canonical fixtures so no view invents its own numbers.
enum SurgePreviewFixtures {
    static let now = SurgeFixtures.referenceDate

    static var workspaces: [WorkspaceSession] { SurgeFixtures.workspaces }

    static var widgetWorkspace: WorkspaceSession { SurgeFixtures.workspaces[0] }

    static var throughput: [ThroughputSample] {
        let values: [Double] = [
            120, 180, 240, 210, 320, 380, 340, 290, 360, 420, 410, 460, 500, 470, 430, 390,
            340, 300, 280, 330, 370, 400, 380, 412, 440, 420, 390, 360, 330, 412,
        ]
        return values.enumerated().map { index, value in
            ThroughputSample(
                date: now.addingTimeInterval(TimeInterval((index - values.count + 1) * 60)),
                tokensPerSecond: value
            )
        }
    }

    static var today: DailySpendPoint {
        SurgeFixtures.dailySpend.last
            ?? DailySpendPoint(date: now, spendByProvider: ["anthropic": 1.02])
    }

    static func agent(
        model: String = "claude-sonnet",
        provider: String = "anthropic",
        status: AgentStatus = .working,
        contextTokens: Int = 84_000,
        window: Int = 200_000
    ) -> AgentNode {
        AgentNode(
            id: "preview-\(model)-\(status.symbol)",
            provider: provider,
            modelName: model,
            status: status,
            inputTokens: 42_000,
            outputTokens: 8_800,
            cacheHitTokens: 152_000,
            currentContextTokens: contextTokens,
            maxContextWindow: window,
            estimatedCostUSD: 0.30,
            lastTokenAt: now.addingTimeInterval(-8)
        )
    }

    static var fuseStates: [(String, AgentNode)] {
        [
            ("Normal", agent(contextTokens: 84_000)),
            ("High", agent(contextTokens: 156_000)),
            ("Near limit", agent(contextTokens: 186_000)),
            ("Tripped", agent(status: .stalled(since: now.addingTimeInterval(-194)), contextTokens: 150_000)),
            ("Idle", agent(status: .idle(since: now.addingTimeInterval(-240)), contextTokens: 24_000)),
            ("Unknown", agent(provider: "openrouter", status: .noSignal, contextTokens: 0, window: 0)),
        ]
    }
}
