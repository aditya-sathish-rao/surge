import Foundation
import SurgeCore

/// The menu bar item's readout and the sentence VoiceOver reads in its place.
///
/// The PRD wins over the design file here: the copy is the short text form, for example
/// "1 Orch, 2 Workers, $1.42", not a single number.
///
/// The bar carries the amount alone. The words that say how a figure was worked out ("est.",
/// "derived", "quota") are jargon with no room to explain themselves in a menu bar, and the number
/// a person wants at a glance is the amount. The popover shows the figure with its label and a
/// sentence that says what the label means.
struct MenuBarReadout: Equatable {
    let orchestrators: Int
    let workers: Int
    /// Today's spend together with the label it earned.
    let spend: SpendFigure
    let attentionCount: Int

    var agentCount: Int { orchestrators + workers }

    /// True when an agent is stalled or waiting for the user, which is exactly what the store
    /// counts. Working, compacting, idle and done agents never light the bar.
    var needsYou: Bool { attentionCount > 0 }

    /// A different shape rather than a different colour, so the alarm survives Differentiate
    /// Without Color and the template drawing the menu bar applies to it.
    var symbolName: String {
        needsYou ? "exclamationmark.triangle.fill" : "bolt.circle.fill"
    }

    /// The whole label: the counts, the spend, and how many agents need the user in front of them.
    /// Nil when there is nothing worth saying, so the item stays a bare glyph instead of reading
    /// "0 Orchs, 0 Workers, $0.00".
    var text: String? {
        guard
            let summary = SurgeFormatting.menuBarSummary(
                orchestrators: orchestrators,
                workers: workers,
                spend: spend
            )
        else { return nil }
        guard needsYou else { return summary }
        return "\(attentionCount) · \(summary)"
    }

    private var showsSpend: Bool {
        SurgeFormatting.menuBarShowsSpend(agentCount: agentCount, spend: spend)
    }

    /// "Surge. 5 agents, 2 need you. 4 dollars 67 spent today."
    ///
    /// One sentence for the app, what needs attention and what is running, then today's spend. The
    /// glyph carries no meaning of its own to VoiceOver, so everything the bar shows is in here.
    var accessibilityLabel: String {
        var sentences = [runDescription, spendDescription].compactMap { $0 }
        sentences.insert("Surge", at: 0)
        return sentences.joined(separator: ". ") + "."
    }

    private var runDescription: String? {
        guard agentCount > 0 else { return "No agents running" }
        if attentionCount == 1 { return "1 agent needs you" }
        let agents = agentCount == 1 ? "1 agent" : "\(agentCount) agents"
        guard needsYou else { return agents }
        return "\(agents), \(attentionCount) need you"
    }

    private var spendDescription: String? {
        guard showsSpend else { return nil }
        return "\(Self.spokenUSD(spend.amountUSD)) spent today"
    }

    /// Money the way a person says it: "16 dollars 91", "1 dollar", "50 cents".
    static func spokenUSD(_ amount: Double) -> String {
        let totalCents = max(Int((amount * 100).rounded()), 0)
        let dollars = totalCents / 100
        let cents = totalCents % 100
        guard dollars > 0 else {
            guard cents > 0 else { return "0 dollars" }
            return cents == 1 ? "1 cent" : "\(cents) cents"
        }
        let dollarPart = dollars == 1 ? "1 dollar" : "\(dollars) dollars"
        guard cents > 0 else { return dollarPart }
        return "\(dollarPart) \(String(format: "%02d", cents))"
    }
}
