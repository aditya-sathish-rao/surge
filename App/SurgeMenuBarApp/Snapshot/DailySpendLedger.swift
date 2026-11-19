import Foundation
import SurgeCore

/// Builds the daily spend history the Spend tab and the widget show.
///
/// The state store keeps live sessions, not history, so this type watches each agent's cumulative
/// cost and books only the increase into the day it arrives. A snapshot from the previous run seeds
/// both the history and each agent's last cost, so relaunching never counts the same dollars twice.
struct DailySpendLedger: Equatable {
    static let retentionDays = 14

    private struct AgentCost: Equatable {
        var costUSD: Double
        var lastSeenAt: Date
    }

    private var totals: [Date: [String: Double]]
    private var agentCosts: [String: AgentCost]
    private let calendar: Calendar

    init(seed: SurgeSnapshot? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        var totals: [Date: [String: Double]] = [:]
        var agentCosts: [String: AgentCost] = [:]
        if let seed {
            for point in seed.dailySpend {
                totals[calendar.startOfDay(for: point.date)] = point.spendByProvider
            }
            for workspace in seed.workspaces {
                for agent in [workspace.orchestrator] + workspace.workers {
                    agentCosts[agent.id] = AgentCost(costUSD: agent.estimatedCostUSD, lastSeenAt: seed.generatedAt)
                }
            }
        }
        self.totals = totals
        self.agentCosts = agentCosts
    }

    mutating func record(workspaces: [WorkspaceSession], at now: Date) {
        let day = calendar.startOfDay(for: now)
        for workspace in workspaces {
            for agent in [workspace.orchestrator] + workspace.workers {
                let previous = agentCosts[agent.id]?.costUSD ?? 0
                let increase = max(agent.estimatedCostUSD - previous, 0)
                if increase > 0 {
                    var dayTotals = totals[day] ?? [:]
                    dayTotals[agent.provider, default: 0] += increase
                    totals[day] = dayTotals
                }
                agentCosts[agent.id] = AgentCost(costUSD: agent.estimatedCostUSD, lastSeenAt: now)
            }
        }
        prune(before: calendar.date(byAdding: .day, value: -Self.retentionDays, to: day))
    }

    func todayTotal(at now: Date) -> Double {
        (totals[calendar.startOfDay(for: now)] ?? [:]).values.reduce(0, +)
    }

    func todayPoint(at now: Date) -> DailySpendPoint {
        DailySpendPoint(
            date: calendar.startOfDay(for: now),
            spendByProvider: totals[calendar.startOfDay(for: now)] ?? [:]
        )
    }

    /// Contiguous days ending today, so the chart's axis always spans the whole range.
    func lastDays(_ count: Int, at now: Date) -> [DailySpendPoint] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 1)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailySpendPoint(date: day, spendByProvider: totals[day] ?? [:])
        }
    }

    private mutating func prune(before cutoff: Date?) {
        guard let cutoff else { return }
        for day in totals.keys where day < cutoff {
            totals[day] = nil
        }
        for (id, cost) in agentCosts where cost.lastSeenAt < cutoff {
            agentCosts[id] = nil
        }
    }
}
