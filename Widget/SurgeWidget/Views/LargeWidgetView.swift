import SurgeCore
import SurgeUI
import SwiftUI

/// Large is the full tree of one workspace, a 7-day spend chart and the balances: more layers of
/// information, not a stretched Medium (PRD 7.3).
struct LargeWidgetView: View {
    let snapshot: SurgeSnapshot
    let filter: WidgetWorkspaceFilter
    let now: Date

    /// Settle for fewer rows rather than clipping the chart below the tree.
    private static let largeRowLimits = [
        WidgetStyle.maxLargeRows, WidgetStyle.maxLargeRows - 1, WidgetStyle.maxLargeRows - 2,
    ]

    private var workspace: WorkspaceSession? {
        if let id = filter.workspaceID {
            return snapshot.workspaces.first { $0.id == id }
        }
        return WidgetSelection.focusedWorkspace(in: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            WidgetHeaderRow(
                title: WidgetHeader.title(workspaceName: workspace?.name),
                needsYou: workspace.map(WidgetSelection.needsYouCount) ?? 0,
                attentionColor: WidgetStyle.attentionColor(workspaces: workspace.map { [$0] } ?? []),
                calmTrailing: workspace == nil ? nil : WidgetHeader.attention(needing: 0)
            )
            if let workspace {
                tree(workspace)
            } else {
                SurgeEmptyState()
            }
            Spacer(minLength: SurgeSpacing.space1)
            spendChart
            WidgetBalancesRow(balances: snapshot.balances, now: now)
            WidgetFreshnessCaption(generatedAt: snapshot.generatedAt, now: now)
        }
    }

    /// The chart and the footer are fixed, so the tree gets whatever height is left. The freshness
    /// caption and a long tree can both be true at once, so the tree offers three sizes and the
    /// system picks the first that fits instead of clipping the chart underneath.
    @ViewBuilder
    private func tree(_ workspace: WorkspaceSession) -> some View {
        let refs = WidgetSelection.tree(in: workspace)
        ViewThatFits(in: .vertical) {
            ForEach(Self.largeRowLimits, id: \.self) { limit in
                rows(refs, limit: limit)
            }
        }
    }

    private func rows(_ refs: [WidgetAgentRef], limit: Int) -> some View {
        let trimmed = WidgetSelection.trimmed(refs, limit: limit)
        return VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            ForEach(trimmed.visible) { agent in
                WidgetAgentRow(reference: agent, now: now)
            }
            if trimmed.hidden > 0 {
                WidgetOverflowRow(text: WidgetHeader.overflow(trimmed.hidden))
            }
        }
    }

    private var spendChart: some View {
        DailySpendChart(days: snapshot.dailySpend, range: .sevenDays, isWidget: true)
            .padding(SurgeSpacing.space2)
            .background(SurgeColors.tile, in: RoundedRectangle(cornerRadius: SurgeRadius.tile))
            .accessibilityChartDescriptor(WidgetSpendChartDescriptor(days: snapshot.dailySpend))
    }
}
