import SurgeCore
import SwiftUI

/// One agent's context meter for the Usage tab.
public struct AgentContextEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let modelName: String
    public let isSubAgent: Bool
    public let fuse: FusePresentation

    public init(agent: AgentNode, isSubAgent: Bool, now: Date) {
        id = agent.id
        modelName = AgentRowPresentation.displayName(forModel: agent.modelName)
        self.isSubAgent = isSubAgent
        fuse = FusePresentation(agent: agent, now: now)
    }

    public static func make(for workspaces: [WorkspaceSession], now: Date) -> [AgentContextEntry] {
        workspaces.flatMap { workspace in
            [AgentContextEntry(agent: workspace.orchestrator, isSubAgent: false, now: now)]
                + workspace.workers.map { AgentContextEntry(agent: $0, isSubAgent: true, now: now) }
        }
    }
}

/// Context utilization by agent, at the same fixed 0 to 100 axis the rows use.
public struct ContextByAgentList: View {
    private let entries: [AgentContextEntry]
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(workspaces: [WorkspaceSession], now: Date) {
        entries = AgentContextEntry.make(for: workspaces, now: now)
    }

    public init(entries: [AgentContextEntry]) {
        self.entries = entries
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
            SurgeSectionLabel("Context by agent")
            ForEach(entries) { entry in
                row(entry)
            }
        }
    }

    private func row(_ entry: AgentContextEntry) -> some View {
        HStack(spacing: SurgeSpacing.space2) {
            Text(entry.modelName)
                .font(SurgeUIFont.rowName)
                .foregroundStyle(SurgeInk.primary())
                .padding(.leading, entry.isSubAgent ? SurgeUIStyle.subAgentIndent : 0)
                .lineLimit(1)
                .frame(width: SurgeUIStyle.usageNameWidth, alignment: .leading)
            Fuse(entry.fuse)
            Text(entry.fuse.contextLabel)
                .font(SurgeUIFont.rowMeta)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: SurgeUIStyle.contextLabelWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.modelName). \(entry.fuse.accessibilityLabel).")
    }
}
