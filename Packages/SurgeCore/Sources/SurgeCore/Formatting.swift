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

    public static func menuBarReadout(orchestrators: Int, workers: Int, spend: SpendFigure) -> String {
        let orchestratorWord = orchestrators == 1 ? "Orch" : "Orchs"
        let workerWord = workers == 1 ? "Worker" : "Workers"
        return "\(orchestrators) \(orchestratorWord), \(workers) \(workerWord), \(spend.displayText)"
    }

    /// The number and its label as one string, or the word unavailable when there is no figure.
    public static func spend(_ figure: SpendFigure?) -> String {
        figure?.displayText ?? "Cost unavailable"
    }
}
