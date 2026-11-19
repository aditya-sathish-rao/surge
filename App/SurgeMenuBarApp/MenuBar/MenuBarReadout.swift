import Foundation
import SurgeCore

/// The menu bar item's readout and the sentence VoiceOver reads in its place.
///
/// The PRD wins over the design file here: the copy is the short text form, for example
/// "1 Orch, 2 Workers, $1.42", not a single number.
struct MenuBarReadout: Equatable {
    let orchestrators: Int
    let workers: Int
    let spendUSD: Double
    let attentionCount: Int

    var agentCount: Int { orchestrators + workers }
    var needsYou: Bool { attentionCount > 0 }

    var text: String {
        SurgeFormatting.menuBarReadout(orchestrators: orchestrators, workers: workers, spendUSD: spendUSD)
    }

    /// "Surge. 5 agents, 2 need you. 16 dollars 91 spent today."
    var accessibilityLabel: String {
        let agents = agentCount == 1 ? "1 agent" : "\(agentCount) agents"
        let spend = "\(Self.spokenUSD(spendUSD)) spent today"
        if needsYou {
            return "Surge. \(agents), \(attentionCount) need you. \(spend)."
        }
        return "Surge. \(agents). \(spend)."
    }

    /// Money the way a person says it: "16 dollars 91", "1 dollar", "0 dollars 50".
    static func spokenUSD(_ amount: Double) -> String {
        let totalCents = max(Int((amount * 100).rounded()), 0)
        let dollars = totalCents / 100
        let cents = totalCents % 100
        let dollarPart = dollars == 1 ? "1 dollar" : "\(dollars) dollars"
        guard cents > 0 else { return dollarPart }
        return "\(dollarPart) \(String(format: "%02d", cents))"
    }
}
