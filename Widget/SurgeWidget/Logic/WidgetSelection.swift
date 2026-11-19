import Foundation
import SurgeCore

/// All workspaces, or one project. The widget's configuration intent supplies the second case.
public enum WidgetWorkspaceFilter: Equatable, Sendable {
    case all
    case workspace(UUID)

    public init(workspaceID: String?) {
        guard let workspaceID, let id = UUID(uuidString: workspaceID) else {
            self = .all
            return
        }
        self = .workspace(id)
    }

    public var workspaceID: UUID? {
        switch self {
        case .all: nil
        case .workspace(let id): id
        }
    }
}

/// One agent or sub-agent together with the workspace it belongs to, which is all a widget row
/// needs to draw itself and to say itself to VoiceOver.
public struct WidgetAgentRef: Identifiable, Equatable, Sendable {
    public let workspaceID: UUID
    public let workspaceName: String
    public let agent: AgentNode
    /// The model name of the orchestrator a sub-agent belongs to, nil for an orchestrator.
    public let parentModelName: String?

    public init(workspaceID: UUID, workspaceName: String, agent: AgentNode, parentModelName: String? = nil) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.agent = agent
        self.parentModelName = parentModelName
    }

    public var id: String { "\(workspaceID.uuidString)/\(agent.id)" }

    public var isSubAgent: Bool { parentModelName != nil }

    public var needsYou: Bool { agent.status.needsYou }
}

/// The widget's ordering rules: the agent that needs you first, then the one closest to its context
/// limit, then the one that costs the most. Ties break on the workspace and agent so a snapshot
/// always draws in the same order.
public enum WidgetSelection {
    public static func urgencyRank(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingForYou: 0
        case .stalled: 1
        case .working: 2
        case .compacting: 3
        case .idle: 4
        case .done: 5
        case .noSignal: 6
        }
    }

    public static func workspaces(in snapshot: SurgeSnapshot, filter: WidgetWorkspaceFilter) -> [WorkspaceSession] {
        switch filter {
        case .all:
            return snapshot.workspaces
        case .workspace(let id):
            return snapshot.workspaces.filter { $0.id == id }
        }
    }

    /// The workspaces needing attention first, then the ones that cost the most (PRD 6.2).
    public static func orderedWorkspaces(_ workspaces: [WorkspaceSession]) -> [WorkspaceSession] {
        workspaces.sorted { lhs, rhs in
            if lhs.needsYou != rhs.needsYou { return lhs.needsYou }
            if lhs.totalTreeCostUSD != rhs.totalTreeCostUSD { return lhs.totalTreeCostUSD > rhs.totalTreeCostUSD }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func agents(
        in workspace: WorkspaceSession
    ) -> [WidgetAgentRef] {
        let name = workspace.name
        let orchestrator = WidgetAgentRef(
            workspaceID: workspace.id,
            workspaceName: name,
            agent: workspace.orchestrator
        )
        let workers = workspace.workers.map {
            WidgetAgentRef(
                workspaceID: workspace.id,
                workspaceName: name,
                agent: $0,
                parentModelName: workspace.orchestrator.modelName
            )
        }
        return [orchestrator] + workers
    }

    /// The workspace tree as the Large widget draws it: the orchestrator first, then its workers
    /// with the ones needing you at the top (PRD 6.2).
    public static func tree(in workspace: WorkspaceSession) -> [WidgetAgentRef] {
        let refs = agents(in: workspace)
        guard let orchestrator = refs.first else { return [] }
        return [orchestrator] + refs.dropFirst().sorted(by: isMoreUrgent)
    }

    /// The rows that fit, plus how many are left over, so a long tree never spills out of the
    /// widget or gets silently cut without a count.
    public static func trimmed(_ refs: [WidgetAgentRef], limit: Int) -> (visible: [WidgetAgentRef], hidden: Int) {
        let bounded = max(limit, 0)
        guard refs.count > bounded else { return (refs, 0) }
        return (Array(refs.prefix(bounded)), refs.count - bounded)
    }

    /// The four meters the Small widget draws: the agents that moved most recently.
    public static func busiestAgents(in workspaces: [WorkspaceSession], limit: Int) -> [WidgetAgentRef] {
        let refs = workspaces.flatMap(agents(in:))
        let ordered = refs.sorted { lhs, rhs in
            if lhs.agent.lastTokenAt != rhs.agent.lastTokenAt { return lhs.agent.lastTokenAt > rhs.agent.lastTokenAt }
            return isMoreUrgent(lhs, rhs)
        }
        return Array(ordered.prefix(max(limit, 0)))
    }

    /// Every agent and sub-agent of the selected workspaces, most urgent first.
    public static func urgentAgents(
        in snapshot: SurgeSnapshot,
        filter: WidgetWorkspaceFilter,
        limit: Int? = nil
    ) -> [WidgetAgentRef] {
        let refs = workspaces(in: snapshot, filter: filter).flatMap(agents(in:))
        let ordered = refs.sorted(by: isMoreUrgent)
        guard let limit else { return ordered }
        return Array(ordered.prefix(max(limit, 0)))
    }

    public static func isMoreUrgent(_ lhs: WidgetAgentRef, _ rhs: WidgetAgentRef) -> Bool {
        let lhsRank = urgencyRank(lhs.agent.status)
        let rhsRank = urgencyRank(rhs.agent.status)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        let lhsStart = stallStart(lhs.agent.status)
        let rhsStart = stallStart(rhs.agent.status)
        if let lhsStart, let rhsStart, lhsStart != rhsStart {
            return lhsStart < rhsStart
        }
        if lhs.agent.contextUsageRatio != rhs.agent.contextUsageRatio {
            return lhs.agent.contextUsageRatio > rhs.agent.contextUsageRatio
        }
        if lhs.agent.estimatedCostUSD != rhs.agent.estimatedCostUSD {
            return lhs.agent.estimatedCostUSD > rhs.agent.estimatedCostUSD
        }
        if lhs.workspaceID != rhs.workspaceID {
            return lhs.workspaceID.uuidString < rhs.workspaceID.uuidString
        }
        return lhs.agent.id < rhs.agent.id
    }

    /// With the filter on "All", the Large widget shows the workspace that holds the most urgent
    /// agent: the most agents needing you first, then the highest spend.
    public static func focusedWorkspace(in snapshot: SurgeSnapshot) -> WorkspaceSession? {
        snapshot.workspaces.max { lhs, rhs in
            let lhsNeeding = needsYouCount(lhs)
            let rhsNeeding = needsYouCount(rhs)
            if lhsNeeding != rhsNeeding { return lhsNeeding < rhsNeeding }
            if lhs.totalTreeCostUSD != rhs.totalTreeCostUSD { return lhs.totalTreeCostUSD < rhs.totalTreeCostUSD }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
        }
    }

    public static func needsYouCount(in workspaces: [WorkspaceSession]) -> Int {
        workspaces.reduce(0) { $0 + needsYouCount($1) }
    }

    public static func needsYouCount(_ workspace: WorkspaceSession) -> Int {
        let orchestrator = workspace.orchestrator.status.needsYou ? 1 : 0
        return orchestrator + workspace.workers.filter { $0.status.needsYou }.count
    }

    public static func workingCount(in workspaces: [WorkspaceSession]) -> Int {
        workspaces.reduce(0) { total, workspace in
            let orchestrator = workspace.orchestrator.status == .working ? 1 : 0
            return total + orchestrator + workspace.workers.filter { $0.status == .working }.count
        }
    }

    private static func stallStart(_ status: AgentStatus) -> Date? {
        switch status {
        case .stalled(let since): since
        case .idle(let since): since
        default: nil
        }
    }
}
