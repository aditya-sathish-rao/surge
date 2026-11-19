import SurgeCore
import SurgeUI
import SwiftUI

/// The widget's header: the title on the left, and either how many agents need you or the calm line.
struct WidgetHeaderRow: View {
    let title: String
    let needsYou: Int
    let attentionColor: Color
    /// What the right side says when nothing needs you. The Small widget counts its agents, and a
    /// widget with no data at all says nothing rather than claiming every agent is working.
    var calmTrailing: String? = WidgetHeader.attention(needing: 0)
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { WidgetStyle.contrast(appearance, system: systemContrast) }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(WidgetStyle.heading)
                .foregroundStyle(SurgeInk.tertiary(contrastLevel))
                .lineLimit(1)
            Spacer(minLength: 4)
            if needsYou > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(SurgeTypography.sans(11))
                    .foregroundStyle(attentionColor)
                    .accessibilityHidden(true)
                Text(WidgetHeader.attention(needing: needsYou))
                    .font(WidgetStyle.heading)
                    .foregroundStyle(attentionColor)
            } else if let calmTrailing {
                Text(calmTrailing)
                    .font(WidgetStyle.heading)
                    .foregroundStyle(SurgeInk.secondary(contrastLevel))
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The freshness caption. It only exists once the snapshot is more than five minutes old.
struct WidgetFreshnessCaption: View {
    let generatedAt: Date
    let now: Date
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { WidgetStyle.contrast(appearance, system: systemContrast) }

    var body: some View {
        if let caption = WidgetFreshness.caption(generatedAt: generatedAt, now: now) {
            Text(caption)
                .font(WidgetStyle.meta)
                .foregroundStyle(SurgeInk.tertiary(contrastLevel))
                .lineLimit(1)
        }
    }
}

/// One line of account balances: provider dot, provider name, amount, and the Low or Empty word.
/// Balances are never summed; each account shows what it reports (PRD 7.2).
struct WidgetBalancesRow: View {
    let balances: [AccountBalance]
    var limit: Int = 3
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { WidgetStyle.contrast(appearance, system: systemContrast) }

    var body: some View {
        HStack(spacing: SurgeSpacing.space2) {
            ForEach(WidgetBalances.visible(balances, limit: limit)) { balance in
                row(BalancePresentation(balance: balance))
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private func row(_ presentation: BalancePresentation) -> some View {
        HStack(spacing: 3) {
            ProviderDot(provider: presentation.provider, size: 6)
            Text(presentation.providerName)
                .font(WidgetStyle.balanceName)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
            Text(presentation.amountText)
                .font(WidgetStyle.balanceAmount)
                .foregroundStyle(presentation.isUnavailable ? SurgeInk.secondary(contrastLevel) : SurgeInk.primary())
                .monospacedDigit()
            if let qualifier = presentation.qualifier {
                Text(qualifier)
                    .font(WidgetStyle.meta)
                    .foregroundStyle(presentation.qualifierColor ?? SurgeInk.secondary(contrastLevel))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
