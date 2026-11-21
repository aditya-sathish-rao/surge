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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { WidgetStyle.contrast(appearance, system: systemContrast) }
    private var reduceMotion: Bool { appearance?.reduceMotion ?? systemReduceMotion }

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
            VStack(alignment: .leading, spacing: 0) {
                Text("\(working)")
                    .font(WidgetStyle.readout)
                    .tracking(WidgetStyle.readoutTracking)
                    .foregroundStyle(SurgeInk.primary())
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text(WidgetHeader.calmSubtitle(working: working, workspaceCount: workspaceCount))
                    .font(WidgetStyle.meta)
                    .foregroundStyle(SurgeInk.secondary(contrastLevel))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetHeader.calmVoiceOver(working: working, workspaceCount: workspaceCount))
            HStack(alignment: .bottom, spacing: SurgeSpacing.space2) {
                ForEach(fuseAgents) { agent in
                    miniFuse(agent)
                }
            }
            .frame(height: WidgetStyle.miniFuseLength, alignment: .bottom)
            .padding(.top, SurgeSpacing.space1)
        }
    }

    private func needsYouBody(agent: WidgetAgentRef, others: Int) -> some View {
        let presentation = presentation(for: agent)
        return VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            Image(systemName: presentation.stateSymbol)
                .font(SurgeTypography.sans(18))
                .foregroundStyle(WidgetStyle.statusColor(for: presentation.status, contrast: contrastLevel))
                .accessibilityHidden(true)
            Text(presentation.modelName)
                .font(WidgetStyle.heroName)
                .foregroundStyle(SurgeInk.primary())
                .lineLimit(1)
            WidgetStatusText(
                status: presentation.status,
                color: WidgetStyle.statusColor(for: presentation.status, contrast: contrastLevel),
                label: SurgeFormatting.statusLabel(presentation.status, now: now)
            )
            .font(WidgetStyle.meta)
            Text(provenance(agent))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRow(presentation: presentation, others: others))
    }

    /// The row is one VoiceOver element, and it says the same sentence the Medium and Large rows do,
    /// then how many others are waiting. The visible sub-agent note is already inside that sentence.
    private func spokenRow(presentation: AgentRowPresentation, others: Int) -> String {
        guard others > 0 else { return presentation.accessibilityLabel }
        return "\(presentation.accessibilityLabel) \(WidgetHeader.othersNeedingVoiceOver(others))"
    }

    /// Aggregated once so the visible words, the Fuse and the spoken sentence can never disagree.
    private func presentation(for agent: WidgetAgentRef) -> AgentRowPresentation {
        AgentRowPresentation(
            agent: agent.agent,
            workspaceName: agent.workspaceName,
            now: now,
            kind: agent.parentModelName.map {
                .subAgent(parentName: AgentRowPresentation.displayName(forModel: $0))
            } ?? .agent
        )
    }

    /// Which workspace the agent runs in, and whether it is a sub-agent.
    private func provenance(_ agent: WidgetAgentRef) -> String {
        let kind = agent.isSubAgent ? "sub-agent" : "agent"
        return "\(agent.workspaceName) · \(kind)"
    }

    /// The same Fuse the popover draws, turned on its end: a capsule with the two notches, so the
    /// four mini meters still read without colour.
    private func miniFuse(_ agent: WidgetAgentRef) -> some View {
        let presentation = presentation(for: agent)
        return Fuse(presentation.fuse, size: .hero)
            .frame(width: WidgetStyle.miniFuseLength, height: WidgetStyle.miniFuseWidth)
            .rotationEffect(.degrees(-90))
            .frame(width: WidgetStyle.miniFuseWidth, height: WidgetStyle.miniFuseLength)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
    }
}
