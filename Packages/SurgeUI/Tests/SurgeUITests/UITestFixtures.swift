import Foundation
import SurgeCore

/// Shared builders for the SurgeUI tests. They reuse `SurgeFixtures.referenceDate` so no test
/// depends on the machine's clock.
enum UITestFixtures {
    static let now = SurgeFixtures.referenceDate

    static func agent(
        id: String = "agent",
        provider: String = "anthropic",
        modelName: String = "claude-sonnet",
        status: AgentStatus = .working,
        contextTokens: Int = 84_000,
        window: Int = 200_000,
        lastTokenAt: Date? = nil
    ) -> AgentNode {
        AgentNode(
            id: id,
            provider: provider,
            modelName: modelName,
            status: status,
            inputTokens: 42_000,
            outputTokens: 8_800,
            cacheHitTokens: 152_000,
            currentContextTokens: contextTokens,
            maxContextWindow: window,
            estimatedCostUSD: 0.30,
            lastTokenAt: lastTokenAt ?? now.addingTimeInterval(-8)
        )
    }
}
