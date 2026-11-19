import AppKit
import SurgeCore
import SurgeStateStore
import SurgeUI
import SwiftUI

/// The Agents tab: workspace chips, the agent tree with expandable rows, then balances.
struct AgentsTab: View {
    let model: AppModel
    @Binding var filter: WorkspaceFilter
    @Binding var expandedAgentID: String?
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var workspaces: [WorkspaceRow] {
        let rows = model.storeModel.workspaces
        guard case .workspace(let id) = filter else { return rows }
        return rows.filter { $0.id == id }
    }

    var body: some View {
        VStack(spacing: SurgeSpacing.cardGap) {
            if model.storeModel.workspaces.isEmpty {
                SurgeCard { SurgeEmptyState() }
            } else {
                treeCard
            }
            BalancesCard(balances: model.storeModel.balances, now: model.now)
        }
    }

    private var treeCard: some View {
        SurgeCard {
            VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
                WorkspaceChips(workspaces: model.workspaces, selection: $filter)
                ForEach(workspaces) { row in
                    workspaceSection(row)
                }
            }
        }
    }

    private func workspaceSection(_ row: WorkspaceRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader(row)
            ForEach(agents(in: row.workspace)) { entry in
                AgentRowItem(
                    model: model,
                    workspace: row.workspace,
                    agent: entry.agent,
                    isSubAgent: entry.isSubAgent,
                    expandedAgentID: $expandedAgentID
                )
            }
        }
        .padding(.top, SurgeSpacing.space1)
    }

    private func workspaceHeader(_ row: WorkspaceRow) -> some View {
        let workspace = row.workspace
        return VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            HStack(spacing: SurgeSpacing.space2) {
                Text(workspace.name)
                    .font(SurgeTypography.title)
                    .foregroundStyle(SurgeInk.primary())
                    .lineLimit(1)
                if row.attentionCount > 0 {
                    HStack(spacing: SurgeSpacing.space1) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(row.attentionCount)")
                            .monospacedDigit()
                    }
                    .font(SurgeTypography.label)
                    .foregroundStyle(SurgeColors.caution)
                }
                Spacer(minLength: SurgeSpacing.space2)
                Text(SurgeFormatting.cost(workspace.totalTreeCostUSD))
                    .font(SurgeTypography.meta)
                    .foregroundStyle(SurgeInk.secondary(systemContrast))
                    .monospacedDigit()
            }
            Text(workspace.projectPath)
                .font(SurgeTypography.path)
                .foregroundStyle(SurgeInk.tertiary(systemContrast))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(workspaceAccessibilityLabel(workspace: workspace, attention: row.attentionCount))
    }

    private func workspaceAccessibilityLabel(workspace: WorkspaceSession, attention: Int) -> String {
        let agents = 1 + workspace.workers.count
        let agentText = agents == 1 ? "1 agent" : "\(agents) agents"
        let spend = SurgeFormatting.cost(workspace.totalTreeCostUSD)
        if attention > 0 {
            return "\(workspace.name), \(workspace.projectPath). \(agentText), \(attention) need you. \(spend)."
        }
        return "\(workspace.name), \(workspace.projectPath). \(agentText). \(spend)."
    }

    private func agents(in workspace: WorkspaceSession) -> [AgentEntry] {
        [AgentEntry(agent: workspace.orchestrator, isSubAgent: false)]
            + workspace.workers.map { AgentEntry(agent: $0, isSubAgent: true) }
    }
}

private struct AgentEntry: Identifiable {
    let agent: AgentNode
    let isSubAgent: Bool

    var id: String { agent.id }
}

/// One agent row, its inline detail when expanded, and its utility menu.
private struct AgentRowItem: View {
    let model: AppModel
    let workspace: WorkspaceSession
    let agent: AgentNode
    let isSubAgent: Bool
    @Binding var expandedAgentID: String?
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var isExpanded: Bool { expandedAgentID == agent.id }

    private var presentation: AgentRowPresentation {
        AgentRowPresentation(
            agent: agent,
            workspaceName: workspace.name,
            tokensPerSecond: model.tokensPerSecond(for: agent.id),
            now: model.now,
            kind: isSubAgent
                ? .subAgent(parentName: AgentRowPresentation.displayName(forModel: workspace.orchestrator.modelName))
                : .agent
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentRow(presentation)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpanded() }
                .focusable()
                .onKeyPress(.return) {
                    toggleExpanded()
                    return .handled
                }
                .onKeyPress(.space) {
                    toggleExpanded()
                    return .handled
                }
                .contextMenu { menuItems }
            if isExpanded {
                detail
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            detailLine("Tokens", TokenCounts.text(for: agent))
            detailLine("Session ID", agent.id, monospaced: true)
            detailLine("Working directory", workspace.projectPath, monospaced: true)
        }
        .padding(.leading, isSubAgent ? AgentRowMetrics.subAgentIndent : 0)
        .padding(.vertical, SurgeSpacing.space1)
        .accessibilityElement(children: .combine)
    }

    private func detailLine(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SurgeSpacing.space2) {
            Text(title)
                .font(SurgeTypography.label)
                .foregroundStyle(SurgeInk.tertiary(systemContrast))
            Text(value)
                .font(monospaced ? SurgeTypography.path : SurgeTypography.meta)
                .foregroundStyle(SurgeInk.secondary(systemContrast))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Copy Session ID") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(agent.id, forType: .string)
        }
        Button(model.isMuted(agent.id) ? "Unmute Alerts for This Agent" : "Mute Alerts for This Agent") {
            model.toggleMute(agent.id)
        }
        Button("Reveal Working Directory in Finder") {
            revealWorkingDirectory()
        }
    }

    private func toggleExpanded() {
        expandedAgentID = isExpanded ? nil : agent.id
    }

    private func revealWorkingDirectory() {
        let path = workspace.projectPath
        guard FileManager.default.fileExists(atPath: path) else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

private enum TokenCounts {
    static func text(for agent: AgentNode) -> String {
        "\(agent.inputTokens) in · \(agent.outputTokens) out · \(agent.cacheHitTokens) cache"
    }
}

/// The sub-agent indent the design system gives `AgentRow`, repeated here for the inline detail.
private enum AgentRowMetrics {
    static let subAgentIndent: CGFloat = 16
}
