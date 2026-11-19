import Foundation
import SurgeCore

/// One agent as the notifier sees it.
struct AgentAlertState: Equatable, Sendable {
    let id: String
    let modelName: String
    let workspaceName: String
    let status: AgentStatus
}

/// The levels Surge is allowed to use. Waiting and stall are active unless the user opts a stall
/// into Time Sensitive; a completed session is Passive and only when asked for.
enum AlertLevel: String, Equatable, Sendable {
    case active
    case timeSensitive
    case passive
}

enum AgentAlertKind: String, Equatable, Sendable {
    case waiting
    case stalled
    case done
}

struct AgentAlert: Equatable, Sendable {
    let agentID: String
    let kind: AgentAlertKind
    let level: AlertLevel
    let title: String
    let body: String

    var identifier: String {
        "surge.\(kind.rawValue).\(agentID)"
    }
}

struct NotificationOptions: Equatable, Sendable {
    var mutedAgentIDs: Set<String> = []
    var stallTimeSensitive = false
    var completionPassive = false
}

/// Chooses which notifications to post for a change in the agent tree.
///
/// The first evaluation only records the current states, so launching Surge never announces
/// everything that was already running. After that, one alert is chosen per agent whose state
/// crossed into waiting, stalled or done. Muted agents still update their recorded state.
struct NotificationPlanner: Equatable {
    private var statuses: [String: AgentStatus] = [:]
    private var hasObserved = false

    mutating func evaluate(
        agents: [AgentAlertState],
        options: NotificationOptions,
        now: Date
    ) -> [AgentAlert] {
        defer {
            statuses = Dictionary(agents.map { ($0.id, $0.status) }, uniquingKeysWith: { _, latest in latest })
            hasObserved = true
        }
        guard hasObserved else { return [] }
        return agents.compactMap { agent in
            guard !options.mutedAgentIDs.contains(agent.id) else { return nil }
            guard let previous = statuses[agent.id], !Self.isSamePhase(previous, agent.status) else {
                return nil
            }
            return alert(for: agent, options: options, now: now)
        }
    }

    private func alert(for agent: AgentAlertState, options: NotificationOptions, now: Date) -> AgentAlert? {
        switch agent.status {
        case .waitingForYou:
            return AgentAlert(
                agentID: agent.id,
                kind: .waiting,
                level: .active,
                title: "\(agent.modelName) is waiting for you",
                body: "Waiting for your input in \(agent.workspaceName)."
            )
        case .stalled(let since):
            return AgentAlert(
                agentID: agent.id,
                kind: .stalled,
                level: options.stallTimeSensitive ? .timeSensitive : .active,
                title: "\(agent.modelName) stalled",
                body: "No tokens for \(Self.spokenDuration(since: since, now: now)) in \(agent.workspaceName)."
            )
        case .done:
            guard options.completionPassive else { return nil }
            return AgentAlert(
                agentID: agent.id,
                kind: .done,
                level: .passive,
                title: "\(agent.modelName) finished",
                body: "Session ended in \(agent.workspaceName)."
            )
        case .working, .compacting, .idle, .noSignal:
            return nil
        }
    }

    private static func isSamePhase(_ lhs: AgentStatus, _ rhs: AgentStatus) -> Bool {
        switch (lhs, rhs) {
        case (.working, .working), (.waitingForYou, .waitingForYou), (.compacting, .compacting),
            (.done, .done), (.noSignal, .noSignal):
            true
        case (.stalled, .stalled), (.idle, .idle):
            true
        default:
            false
        }
    }

    /// "2 minutes", the way the design's notification copy reads.
    static func spokenDuration(since start: Date, now: Date) -> String {
        let minutes = max(Int(now.timeIntervalSince(start) / 60), 1)
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
