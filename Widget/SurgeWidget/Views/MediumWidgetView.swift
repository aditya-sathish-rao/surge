import SurgeCore
import SurgeUI
import SwiftUI

/// Medium lists the four most urgent agents or sub-agents, one row each, plus the account balances
/// (PRD 7.3).
struct MediumWidgetView: View {
    let snapshot: SurgeSnapshot
    let filter: WidgetWorkspaceFilter
    let now: Date

    private static let rowLimit = 4

    private var workspaces: [WorkspaceSession] {
        WidgetSelection.workspaces(in: snapshot, filter: filter)
    }

    private var agents: [WidgetAgentRef] {
        WidgetSelection.urgentAgents(in: snapshot, filter: filter, limit: Self.rowLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetStyle.compactSpacing) {
            WidgetHeaderRow(
                title: WidgetHeader.title(workspaceName: workspaces.count == 1 ? workspaces[0].name : nil),
                needsYou: WidgetSelection.needsYouCount(in: workspaces),
                attentionColor: WidgetStyle.attentionColor(workspaces: workspaces),
                calmTrailing: workspaces.isEmpty ? nil : WidgetHeader.attention(needing: 0)
            )
            if agents.isEmpty {
                SurgeEmptyState()
            } else {
                ForEach(agents) { agent in
                    WidgetAgentRow(reference: agent, now: now)
                }
            }
            Spacer(minLength: SurgeSpacing.space1)
            WidgetBalancesRow(balances: snapshot.balances)
            WidgetFreshnessCaption(generatedAt: snapshot.generatedAt, now: now)
        }
    }
}
