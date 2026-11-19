import SurgeCore
import SurgeUI
import SwiftUI

/// Large is the full tree of one workspace, a 7-day spend chart and the balances: more layers of
/// information, not a stretched Medium (PRD 7.3).
struct LargeWidgetView: View {
    let snapshot: SurgeSnapshot
    let filter: WidgetWorkspaceFilter
    let now: Date

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

    @ViewBuilder
    private func tree(_ workspace: WorkspaceSession) -> some View {
        let rows = WidgetSelection.trimmed(WidgetSelection.tree(in: workspace), limit: WidgetStyle.maxLargeRows)
        ForEach(rows.visible) { agent in
            WidgetAgentRow(reference: agent, now: now)
        }
        if rows.hidden > 0 {
            WidgetOverflowRow(text: WidgetHeader.overflow(rows.hidden))
        }
    }

    private var spendChart: some View {
        DailySpendChart(days: snapshot.dailySpend, range: .sevenDays, isWidget: true)
            .padding(SurgeSpacing.space2)
            .background(SurgeColors.tile, in: RoundedRectangle(cornerRadius: SurgeRadius.tile))
    }
}
