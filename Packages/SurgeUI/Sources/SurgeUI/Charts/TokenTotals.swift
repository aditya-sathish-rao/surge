import SurgeCore
import SwiftUI

/// Token totals for one agent, summed from the counters the pipelines publish.
public struct AgentTokenTotals: Identifiable, Sendable, Equatable {
    public let id: String
    public let modelName: String
    public let provider: Provider
    public let isSubAgent: Bool
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheHitTokens: Int

    public init(agent: AgentNode, isSubAgent: Bool) {
        id = agent.id
        modelName = AgentRowPresentation.displayName(forModel: agent.modelName)
        provider = agent.providerKind
        self.isSubAgent = isSubAgent
        inputTokens = agent.inputTokens
        outputTokens = agent.outputTokens
        cacheHitTokens = agent.cacheHitTokens
    }

    /// Every orchestrator and sub-agent in workspace order, each sub-agent after its agent.
    public static func make(for workspaces: [WorkspaceSession]) -> [AgentTokenTotals] {
        workspaces.flatMap { workspace in
            [AgentTokenTotals(agent: workspace.orchestrator, isSubAgent: false)]
                + workspace.workers.map { AgentTokenTotals(agent: $0, isSubAgent: true) }
        }
    }
}

/// Token counts read the same on every machine: 152,000 is "152K", never a locale-specific lakh.
public enum TokenCountFormat {
    private static let locale = Locale(identifier: "en_US")

    public static func text(_ value: Int) -> String {
        max(value, 0).formatted(.number.notation(.compactName).locale(locale))
    }
}

/// Token totals by agent: input, output and cache hit counts for every session on screen.
public struct TokenTotalsList: View {
    private let totals: [AgentTokenTotals]
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(workspaces: [WorkspaceSession]) {
        totals = AgentTokenTotals.make(for: workspaces)
    }

    public init(totals: [AgentTokenTotals]) {
        self.totals = totals
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
            SurgeSectionLabel("Token totals")
            header
            ForEach(totals) { total in
                row(total)
            }
        }
    }

    private var header: some View {
        HStack(spacing: SurgeSpacing.space2) {
            Spacer(minLength: 0)
            ForEach(columns, id: \.self) { column in
                Text(column)
                    .font(SurgeUIFont.sectionLabel)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
                    .frame(width: SurgeUIStyle.tokenColumnWidth, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private func row(_ total: AgentTokenTotals) -> some View {
        HStack(spacing: SurgeSpacing.space2) {
            HStack(spacing: SurgeSpacing.space1) {
                ProviderDot(provider: total.provider)
                Text(total.modelName)
                    .font(SurgeUIFont.rowName)
                    .foregroundStyle(SurgeInk.primary())
                    .lineLimit(1)
            }
            .padding(.leading, total.isSubAgent ? SurgeUIStyle.subAgentIndent : 0)
            Spacer(minLength: SurgeSpacing.space2)
            count(total.inputTokens)
            count(total.outputTokens)
            count(total.cacheHitTokens)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(total))
    }

    private func count(_ value: Int) -> some View {
        Text(TokenCountFormat.text(value))
            .font(SurgeUIFont.rowMeta)
            .foregroundStyle(SurgeInk.secondary(contrastLevel))
            .monospacedDigit()
            .frame(width: SurgeUIStyle.tokenColumnWidth, alignment: .trailing)
    }

    private var columns: [String] { ["In", "Out", "Cache"] }

    private func accessibilityLabel(_ total: AgentTokenTotals) -> String {
        "\(total.modelName), \(total.inputTokens) input tokens, \(total.outputTokens) output tokens, "
            + "\(total.cacheHitTokens) cache hit tokens"
    }
}
