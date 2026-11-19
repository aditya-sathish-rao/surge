import SurgeCore
import SurgeUI
import SwiftUI

/// Small answers "is anything wrong?". One number and four mini Fuses when everything is calm, or
/// the agent that needs you, its state and how many others are waiting (PRD 7.3).
struct SmallWidgetView: View {
    let snapshot: SurgeSnapshot
    let filter: WidgetWorkspaceFilter
    let now: Date
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { WidgetStyle.contrast(appearance, system: systemContrast) }

    private var content: WidgetSmallContent { WidgetSmallContent(snapshot: snapshot, filter: filter) }

    private var workspaces: [WorkspaceSession] {
        WidgetSelection.workspaces(in: snapshot, filter: filter)
    }

    private var needsYou: Int {
        WidgetSelection.needsYouCount(in: workspaces)
    }

    private var agentCount: Int {
        workspaces.reduce(0) { $0 + 1 + $1.workers.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeaderRow(
                title: "Surge",
                needsYou: needsYou,
                attentionColor: WidgetStyle.attentionColor(workspaces: workspaces),
                calmTrailing: workspaces.isEmpty ? nil : WidgetHeader.agentCount(agentCount)
            )
            Spacer(minLength: SurgeSpacing.space1)
            body(for: content)
            Spacer(minLength: 0)
            WidgetFreshnessCaption(generatedAt: snapshot.generatedAt, now: now)
        }
    }

    @ViewBuilder
    private func body(for content: WidgetSmallContent) -> some View {
        switch content {
        case .noAgents:
            SurgeEmptyState()
        case .calm(let working, let workspaceCount, let fuseAgents):
            calmBody(working: working, workspaceCount: workspaceCount, fuseAgents: fuseAgents)
        case .needsYou(let agent, let others):
            needsYouBody(agent: agent, others: others)
        }
    }

    private func calmBody(working: Int, workspaceCount: Int, fuseAgents: [WidgetAgentRef]) -> some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            Text("\(working)")
                .font(WidgetStyle.readout)
                .tracking(WidgetStyle.readoutTracking)
                .foregroundStyle(SurgeInk.primary())
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel(working == 1 ? "1 agent working" : "\(working) agents working")
            Text(WidgetHeader.calmSubtitle(working: working, workspaceCount: workspaceCount))
                .font(WidgetStyle.meta)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
                .lineLimit(1)
            HStack(alignment: .bottom, spacing: SurgeSpacing.space2) {
                ForEach(fuseAgents) { agent in
                    miniFuse(FusePresentation(agent: agent.agent, now: now))
                }
            }
            .frame(height: WidgetStyle.miniFuseLength, alignment: .bottom)
            .padding(.top, SurgeSpacing.space1)
        }
    }

    private func needsYouBody(agent: WidgetAgentRef, others: Int) -> some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            Image(systemName: agent.agent.status.symbol)
                .font(SurgeTypography.sans(18))
                .foregroundStyle(WidgetStyle.statusColor(for: agent.agent.status, contrast: contrastLevel))
            Text(AgentRowPresentation.displayName(forModel: agent.agent.modelName))
                .font(SurgeTypography.sans(13, weight: .medium))
                .foregroundStyle(SurgeInk.primary())
                .lineLimit(1)
            WidgetStatusText(
                status: agent.agent.status,
                color: WidgetStyle.statusColor(for: agent.agent.status, contrast: contrastLevel),
                label: SurgeFormatting.statusLabel(agent.agent.status, now: now)
            )
            .font(WidgetStyle.meta)
            Text(role(agent))
                .font(WidgetStyle.meta)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
                .lineLimit(1)
            if others > 0 {
                Text(WidgetHeader.othersNeeding(others))
                    .font(WidgetStyle.meta)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func role(_ agent: WidgetAgentRef) -> String {
        let role = agent.isSubAgent ? "sub-agent" : "agent"
        return "\(agent.workspaceName) · \(role)"
    }

    /// The same Fuse the popover draws, turned on its end: a capsule with the two notches, so the
    /// four mini meters still read without colour.
    private func miniFuse(_ presentation: FusePresentation) -> some View {
        Fuse(presentation, size: .hero)
            .frame(width: WidgetStyle.miniFuseLength, height: WidgetStyle.miniFuseWidth)
            .rotationEffect(.degrees(-90))
            .frame(width: WidgetStyle.miniFuseWidth, height: WidgetStyle.miniFuseLength)
    }
}
