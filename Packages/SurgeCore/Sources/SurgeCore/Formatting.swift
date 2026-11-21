import Foundation

public enum SurgeFormatting {
    private static let dollars = Locale(identifier: "en_US")

    public static func cost(_ amountUSD: Double) -> String {
        amountUSD.formatted(.currency(code: "USD").locale(dollars))
    }

    public static func percent(_ ratio: Double) -> String {
        let clamped = min(max(ratio, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    public static func tokenRate(_ tokensPerSecond: Double) -> String {
        "\(Int(max(tokensPerSecond, 0).rounded())) tok/s"
    }

    public static func duration(since start: Date, now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    public static func minutesDuration(since start: Date, now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    public static func statusLabel(
        _ status: AgentStatus,
        now: Date,
        lastActivityAt: Date? = nil
    ) -> String {
        switch status {
        case .working:
            return "Working"
        case .waitingForYou:
            return "Waiting for you"
        case .stalled(let since):
            return "Stalled \(duration(since: since, now: now))"
        case .compacting:
            return "Compacting"
        case .idle(let since):
            return "Idle \(minutesDuration(since: since, now: now))"
        case .done:
            guard let lastActivityAt else { return "Done" }
            return "Done · \(minutesDuration(since: lastActivityAt, now: now))"
        case .noSignal:
            return "No signal"
        }
    }

    public static func balanceLabel(_ balance: AccountBalance) -> String {
        if let window = balance.quotaWindow {
            return "\(window.percentUsed)% of window"
        }
        guard let amount = balance.amountUSD else { return "Balance unavailable" }
        switch SurgeThresholds.balanceLevel(forUSD: amount) {
        case .normal:
            return cost(amount)
        case .low:
            return "\(cost(amount)) · Low"
        case .empty:
            return "\(cost(amount)) · Empty"
        }
    }

    @available(*, deprecated, message: "Use menuBarSummary(orchestrators:workers:spend:) for the menu bar readout.")
    public static func menuBarReadout(orchestrators: Int, workers: Int, spend: SpendFigure) -> String {
        let orchestratorWord = orchestrators == 1 ? "Orch" : "Orchs"
        let workerWord = workers == 1 ? "Worker" : "Workers"
        return "\(orchestrators) \(orchestratorWord), \(workers) \(workerWord), \(spend.displayText)"
    }

    /// "1 Orch, 2 Workers, $1.42". A count of zero is left out, so four orchestrators and no
    /// workers read "4 Orchs, $4.58" rather than carrying a dead "0 Workers" field. Nil when
    /// there is nothing worth saying, so the item stays a bare glyph.
    public static func menuBarSummary(
        orchestrators: Int,
        workers: Int,
        spend: SpendFigure
    ) -> String? {
        let fields = [
            orchestratorField(orchestrators),
            workerField(workers),
            spendField(spend, agentCount: orchestrators + workers),
        ].compactMap { $0 }
        return fields.isEmpty ? nil : fields.joined(separator: ", ")
    }

    /// True when the menu bar has a spend figure worth showing. An amount nothing could report is
    /// left out, and so is a zero from a day with no agents running.
    public static func menuBarShowsSpend(agentCount: Int, spend: SpendFigure) -> Bool {
        spend.source != .unavailable && (agentCount > 0 || spend.amountUSD > 0)
    }

    private static func orchestratorField(_ orchestrators: Int) -> String? {
        guard orchestrators > 0 else { return nil }
        return "\(orchestrators) \(orchestrators == 1 ? "Orch" : "Orchs")"
    }

    private static func workerField(_ workers: Int) -> String? {
        guard workers > 0 else { return nil }
        return workers == 1 ? "1 Worker" : "\(workers) Workers"
    }

    private static func spendField(_ spend: SpendFigure, agentCount: Int) -> String? {
        guard menuBarShowsSpend(agentCount: agentCount, spend: spend) else { return nil }
        return spend.amountText
    }

    /// The running agents and anything that needs the user, as one spoken clause. The total count
    /// is always said when more than one agent runs, and the attention clause appears exactly once.
    public static func menuBarRunDescription(agentCount: Int, attentionCount: Int) -> String {
        guard agentCount > 0 else { return "No agents running" }
        guard attentionCount > 0 else { return agentCount == 1 ? "1 agent" : "\(agentCount) agents" }
        guard attentionCount > 1 else {
            return agentCount == 1 ? "1 agent needs you" : "\(agentCount) agents, 1 needs you"
        }
        return "\(agentCount) agents, \(attentionCount) need you"
    }

    /// The number and its label as one string, or the word unavailable when there is no figure.
    public static func spend(_ figure: SpendFigure?) -> String {
        figure?.displayText ?? "Cost unavailable"
    }
}
