import Foundation
import SurgeCore

/// Decides when the widget is asked to reload, independently of when the snapshot is written.
///
/// A reload is asked for at most once every 60 seconds and only when something happened since the
/// last one: an agent crossed working, waiting, stalled or done, a wallet poll completed, or the
/// user opened the popover or panel. Token-only updates never trigger one.
struct WidgetReloadPolicy: Equatable {
    static let minimumInterval: TimeInterval = 60

    enum StatusCategory: Equatable {
        case working
        case waiting
        case stalled
        case done
        case other

        init(_ status: AgentStatus) {
            switch status {
            case .working: self = .working
            case .waitingForYou: self = .waiting
            case .stalled: self = .stalled
            case .done: self = .done
            case .compacting, .idle, .noSignal: self = .other
            }
        }

        /// The four states whose crossing is worth waking the widget for.
        var isReloadWorthy: Bool {
            switch self {
            case .working, .waiting, .stalled, .done: true
            case .other: false
            }
        }
    }

    private var statuses: [String: StatusCategory] = [:]
    private var balancePolls: [String: Date] = [:]
    private var hasObserved = false
    private var pendingTrigger = false
    private var lastReloadAt: Date?

    mutating func note(workspaces: [WorkspaceSession], balances: [AccountBalance]) {
        let currentStatuses = Self.statuses(in: workspaces)
        let currentPolls = Dictionary(
            balances.map { ($0.provider, $0.lastPolledAt) },
            uniquingKeysWith: { _, latest in latest }
        )
        if !hasObserved {
            hasObserved = true
            pendingTrigger = !currentStatuses.isEmpty || !currentPolls.isEmpty
        } else {
            if Self.crossedAStatus(from: statuses, to: currentStatuses) {
                pendingTrigger = true
            }
            if currentPolls != balancePolls {
                pendingTrigger = true
            }
        }
        statuses = currentStatuses
        balancePolls = currentPolls
    }

    mutating func notePopoverOpened() {
        pendingTrigger = true
    }

    mutating func shouldReload(at now: Date) -> Bool {
        guard pendingTrigger else { return false }
        if let lastReloadAt, now.timeIntervalSince(lastReloadAt) < Self.minimumInterval {
            return false
        }
        pendingTrigger = false
        lastReloadAt = now
        return true
    }

    private static func statuses(in workspaces: [WorkspaceSession]) -> [String: StatusCategory] {
        var result: [String: StatusCategory] = [:]
        for workspace in workspaces {
            result[workspace.orchestrator.id] = StatusCategory(workspace.orchestrator.status)
            for worker in workspace.workers {
                result[worker.id] = StatusCategory(worker.status)
            }
        }
        return result
    }

    private static func crossedAStatus(
        from previous: [String: StatusCategory],
        to current: [String: StatusCategory]
    ) -> Bool {
        for (id, category) in current {
            let old = previous[id] ?? .other
            guard old != category else { continue }
            if old.isReloadWorthy || category.isReloadWorthy {
                return true
            }
        }
        return false
    }
}
