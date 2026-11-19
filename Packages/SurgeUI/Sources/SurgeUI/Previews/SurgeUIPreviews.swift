import SurgeCore
import SwiftUI

private struct PreviewRows: View {
    private let workspace = SurgePreviewFixtures.widgetWorkspace

    var body: some View {
        SurgeCard {
            VStack(spacing: 0) {
                AgentRow(
                    AgentRowPresentation(
                        agent: workspace.orchestrator,
                        workspaceName: workspace.name,
                        tokensPerSecond: 68,
                        now: SurgePreviewFixtures.now
                    )
                )
                AgentRow(
                    AgentRowPresentation(
                        agent: workspace.workers[0],
                        workspaceName: workspace.name,
                        now: SurgePreviewFixtures.now,
                        kind: .subAgent(parentName: "Claude Sonnet")
                    )
                )
                AgentRow(
                    AgentRowPresentation(
                        agent: workspace.workers[1],
                        workspaceName: workspace.name,
                        now: SurgePreviewFixtures.now,
                        kind: .subAgent(parentName: "Claude Sonnet")
                    )
                )
            }
        }
        .frame(width: SurgeSize.popoverWidth)
        .padding()
    }
}

private struct PreviewFuseStates: View {
    var body: some View {
        SurgeCard {
            VStack(alignment: .leading, spacing: SurgeSpacing.section) {
                ForEach(SurgePreviewFixtures.fuseStates, id: \.0) { name, agent in
                    let presentation = FusePresentation(agent: agent, now: SurgePreviewFixtures.now)
                    VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
                        Text(name)
                            .font(SurgeUIFont.sectionLabel)
                            .foregroundStyle(SurgeInk.tertiary())
                        HStack(spacing: SurgeSpacing.space2) {
                            Fuse(presentation)
                            Text(presentation.label)
                                .font(SurgeUIFont.rowMeta)
                                .foregroundStyle(SurgeInk.secondary())
                                .monospacedDigit()
                        }
                        Fuse(presentation, size: .hero)
                    }
                }
            }
        }
        .frame(width: SurgeSize.popoverWidth)
        .padding()
    }
}

private struct PreviewTabsAndChips: View {
    @State private var tab: SurgeTab = .agents
    @State private var filter: WorkspaceFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.section) {
            PillTabs(selection: $tab)
            WorkspaceChips(workspaces: SurgePreviewFixtures.workspaces, selection: $filter)
        }
        .padding()
        .frame(width: SurgeSize.popoverWidth)
    }
}

private struct PreviewCards: View {
    var body: some View {
        VStack(spacing: SurgeSpacing.cardGap) {
            BalancesCard(balances: SurgeFixtures.balances, now: SurgePreviewFixtures.now)
            SurgeCard { SurgeEmptyState() }
        }
        .padding()
        .frame(width: SurgeSize.popoverWidth)
    }
}

private struct PreviewCharts: View {
    var body: some View {
        VStack(spacing: SurgeSpacing.cardGap) {
            SurgeCard {
                ThroughputChart(samples: SurgePreviewFixtures.throughput)
            }
            SurgeCard {
                DailySpendChart(days: SurgeFixtures.dailySpend)
            }
            SurgeCard {
                SpendByProviderBar(shares: SpendShares.make(for: SurgePreviewFixtures.today))
            }
            SurgeCard {
                VStack(alignment: .leading, spacing: SurgeSpacing.section) {
                    TokenTotalsList(workspaces: SurgePreviewFixtures.workspaces)
                    ContextByAgentList(workspaces: SurgePreviewFixtures.workspaces, now: SurgePreviewFixtures.now)
                }
            }
        }
        .padding()
        .frame(width: SurgeSize.popoverWidth)
    }
}

#Preview("Agent rows, light") {
    PreviewRows()
        .preferredColorScheme(.light)
}

#Preview("Agent rows, dark") {
    PreviewRows()
        .preferredColorScheme(.dark)
}

#Preview("Agent rows, increased contrast, reduce motion") {
    PreviewRows()
        .surgeAppearance(SurgeAppearance(contrast: .increased, reduceMotion: true))
        .preferredColorScheme(.dark)
}

#Preview("Fuse states, light") {
    PreviewFuseStates()
        .preferredColorScheme(.light)
}

#Preview("Fuse states, dark, increased contrast") {
    PreviewFuseStates()
        .surgeAppearance(SurgeAppearance(contrast: .increased))
        .preferredColorScheme(.dark)
}

#Preview("Tabs and chips, dark, reduce motion") {
    PreviewTabsAndChips()
        .surgeAppearance(SurgeAppearance(reduceMotion: true))
        .preferredColorScheme(.dark)
}

#Preview("Tabs and chips, light") {
    PreviewTabsAndChips()
        .preferredColorScheme(.light)
}

#Preview("Balances and empty state, dark") {
    PreviewCards()
        .preferredColorScheme(.dark)
}

#Preview("Charts, light") {
    PreviewCharts()
        .preferredColorScheme(.light)
}

#Preview("Charts, dark, increased contrast") {
    PreviewCharts()
        .surgeAppearance(SurgeAppearance(contrast: .increased))
        .preferredColorScheme(.dark)
}
