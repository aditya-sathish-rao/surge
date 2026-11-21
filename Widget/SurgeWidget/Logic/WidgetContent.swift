import Foundation
import SurgeCore

/// What the Small widget shows: the quiet case answers "how much is working?", and the moment any
/// agent needs the user, that agent's name and state replace it (PRD 7.3).
public enum WidgetSmallContent: Equatable, Sendable {
    case noAgents
    case calm(working: Int, workspaceCount: Int, fuseAgents: [WidgetAgentRef])
    case needsYou(agent: WidgetAgentRef, others: Int)

    public static let fuseAgentCount = 4

    public init(snapshot: SurgeSnapshot, filter: WidgetWorkspaceFilter) {
        let workspaces = WidgetSelection.workspaces(in: snapshot, filter: filter)
        guard !workspaces.isEmpty else {
            self = .noAgents
            return
        }

        let agents = WidgetSelection.urgentAgents(in: snapshot, filter: filter)
        if let urgent = agents.first, urgent.needsYou {
            self = .needsYou(agent: urgent, others: agents.filter(\.needsYou).count - 1)
            return
        }

        let working = WidgetSelection.workingCount(in: workspaces)
        let workingWorkspaces = workspaces.filter { workspace in
            WidgetSelection.agents(in: workspace).contains { $0.agent.status == .working }
        }
        self = .calm(
            working: working,
            workspaceCount: workingWorkspaces.count,
            fuseAgents: WidgetSelection.busiestAgents(in: workspaces, limit: Self.fuseAgentCount)
        )
    }
}

/// The staleness wording. The widget never shows old data as if it were live: once the snapshot is
/// more than five minutes old, it says how old the data is (PRD 8, TRD 6.2).
public enum WidgetFreshness {
    public static let staleThreshold = SurgeThresholds.snapshotStaleSeconds

    public static func caption(generatedAt: Date, now: Date) -> String? {
        let age = now.timeIntervalSince(generatedAt)
        guard age > staleThreshold else { return nil }
        let minutes = max(Int(age / 60), 1)
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours < 24 {
            return remainder == 0 ? "Updated \(hours)h ago" : "Updated \(hours)h \(remainder)m ago"
        }
        return "Updated \(hours / 24)d ago"
    }
}

/// The status word a widget row can fit beside its Fuse. The full sentence stays in the row's
/// VoiceOver label, and stalled and idle rows let the system timer count for them.
public enum WidgetStatusWording {
    public static func short(_ status: AgentStatus) -> String {
        switch status {
        case .working: "Working"
        case .waitingForYou: "Waiting for you"
        case .compacting: "Compacting"
        case .stalled: "Stalled"
        case .idle: "Idle"
        case .done: "Done"
        case .noSignal: "No signal"
        }
    }
}

/// The balances a widget footer has room for. Accounts that report a balance come first; when none
/// does, the unavailable one still says so rather than the footer disappearing.
public enum WidgetBalances {
    public static func visible(_ balances: [AccountBalance], limit: Int) -> [AccountBalance] {
        let available = balances.filter(\.isAvailable)
        let ordered = available.isEmpty ? balances : available
        return Array(ordered.prefix(max(limit, 0)))
    }
}

/// The header's title and attention line.
public enum WidgetHeader {
    public static let allWorkspaces = "all workspaces"

    public static func title(workspaceName: String?) -> String {
        guard let workspaceName else { return "Surge · \(allWorkspaces)" }
        return "Surge · \(workspaceName)"
    }

    public static func attention(needing: Int) -> String {
        guard needing > 0 else { return "All agents working" }
        return needing == 1 ? "1 needs you" : "\(needing) need you"
    }

    /// "+1 waiting for you" in the design system; pluralised without inventing a new word.
    public static func othersNeeding(_ count: Int) -> String {
        count == 1 ? "+1 waiting for you" : "+\(count) waiting for you"
    }

    /// The spoken form of the "+2 waiting for you" line, which is a sentence where the visible line
    /// is a fragment.
    public static func othersNeedingVoiceOver(_ count: Int) -> String {
        count == 1 ? "1 more agent is waiting for you." : "\(count) more agents are waiting for you."
    }

    /// The line under a tree that had more rows than the widget could draw.
    public static func overflow(_ count: Int) -> String {
        count == 1 ? "+1 more agent" : "+\(count) more agents"
    }

    /// "4 agents" beside the Small widget's title.
    public static func agentCount(_ count: Int) -> String {
        count == 1 ? "1 agent" : "\(count) agents"
    }

    /// "working · 2 workspaces" under the Small widget's readout, and the quiet case for zero.
    public static func calmSubtitle(working: Int, workspaceCount: Int) -> String {
        guard working > 0 else { return "nothing working" }
        let workspaces = workspaceCount == 1 ? "1 workspace" : "\(workspaceCount) workspaces"
        return "working · \(workspaces)"
    }

    /// The calm readout as one spoken sentence. The number and the caption under it are one fact, so
    /// VoiceOver hears them once rather than twice.
    public static func calmVoiceOver(working: Int, workspaceCount: Int) -> String {
        guard working > 0 else { return "No agents working" }
        let agents = working == 1 ? "1 agent working" : "\(working) agents working"
        let workspaces = workspaceCount == 1 ? "1 workspace" : "\(workspaceCount) workspaces"
        return "\(agents) in \(workspaces)"
    }
}

/// Clicking anywhere in the widget opens the panel. The shape is fixed with the app: `surge://panel`
/// with an optional workspace filter.
public enum WidgetDeepLink {
    public static let scheme = "surge"
    public static let host = "panel"

    public static func panelURL(workspaceID: UUID?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let workspaceID {
            components.queryItems = [URLQueryItem(name: "workspace", value: workspaceID.uuidString)]
        }
        return components.url ?? URL(fileURLWithPath: "")
    }

    /// Where a click should land. A filtered widget opens its own workspace; "All" opens the
    /// workspace that made the widget speak up, and the Large layout always opens the one it drew.
    public static func targetWorkspace(
        in snapshot: SurgeSnapshot,
        filter: WidgetWorkspaceFilter,
        layout: WidgetLayout
    ) -> UUID? {
        if let id = filter.workspaceID { return id }
        switch layout {
        case .small, .medium:
            guard let urgent = WidgetSelection.urgentAgents(in: snapshot, filter: filter).first,
                urgent.needsYou
            else { return nil }
            return urgent.workspaceID
        case .large:
            return WidgetSelection.focusedWorkspace(in: snapshot)?.id
        }
    }
}

/// The three widget sizes, named once so the logic and the views agree.
public enum WidgetLayout: Sendable, Equatable {
    case small
    case medium
    case large
}
