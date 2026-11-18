import SurgeCore
import SwiftUI

/// One account row's text. Balances are never summed across providers.
public struct BalancePresentation: Sendable, Equatable {
    public let provider: Provider
    public let providerName: String
    public let amountText: String
    public let level: BalanceLevel?
    public let isUnavailable: Bool
    public let accessibilityLabel: String

    public init(balance: AccountBalance) {
        provider = balance.providerKind
        providerName = balance.providerKind.name
        isUnavailable = !balance.isAvailable
        guard let amount = balance.amountUSD else {
            amountText = "Balance unavailable"
            level = nil
            accessibilityLabel = "\(providerName), balance unavailable"
            return
        }
        amountText = SurgeFormatting.cost(amount)
        let level = SurgeThresholds.balanceLevel(forUSD: amount)
        self.level = level
        accessibilityLabel =
            switch level {
            case .normal: "\(providerName), \(amountText)"
            case .low: "\(providerName), \(amountText), low"
            case .empty: "\(providerName), \(amountText), empty"
            }
    }

    /// The word that appears beside a low or empty account, and only then.
    public var qualifier: String? {
        switch level {
        case .low: "Low"
        case .empty: "Empty"
        case .normal, nil: nil
        }
    }

    public var qualifierColor: Color? {
        switch level {
        case .low: SurgeColors.caution
        case .empty: SurgeColors.alert
        case .normal, nil: nil
        }
    }
}

/// The freshness caption under the balances. Only one clock matters, the wallet poll.
public enum BalanceFreshness {
    public static func caption(lastPolledAt: Date?, now: Date) -> String {
        guard let lastPolledAt else { return "// not polled yet" }
        return "// updated \(SurgeFormatting.duration(since: lastPolledAt, now: now)) ago"
    }

    public static func lastPolledAt(in balances: [AccountBalance]) -> Date? {
        balances.map(\.lastPolledAt).max()
    }
}

/// One row per provider account, with a monospace caption saying how fresh the data is.
public struct BalancesCard: View {
    private let balances: [AccountBalance]
    private let now: Date
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(balances: [AccountBalance], now: Date) {
        self.balances = balances
        self.now = now
    }

    public var body: some View {
        SurgeCard {
            VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
                SurgeSectionLabel("Account balances")
                ForEach(balances) { balance in
                    row(BalancePresentation(balance: balance))
                }
                caption
            }
        }
    }

    private func row(_ presentation: BalancePresentation) -> some View {
        HStack(spacing: SurgeSpacing.space1) {
            ProviderDot(provider: presentation.provider)
            Text(presentation.providerName)
                .font(SurgeUIFont.balanceName)
                .foregroundStyle(SurgeInk.primary())
            if let qualifier = presentation.qualifier {
                Text(qualifier)
                    .font(SurgeUIFont.balanceQualifier)
                    .foregroundStyle(presentation.qualifierColor ?? SurgeInk.secondary(contrastLevel))
            }
            Spacer(minLength: SurgeSpacing.space2)
            Text(presentation.amountText)
                .font(SurgeUIFont.balanceAmount)
                .foregroundStyle(
                    presentation.isUnavailable ? SurgeInk.secondary(contrastLevel) : SurgeInk.primary()
                )
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var caption: some View {
        if !balances.isEmpty {
            Text(BalanceFreshness.caption(lastPolledAt: BalanceFreshness.lastPolledAt(in: balances), now: now))
                .font(SurgeUIFont.balanceCaption)
                .foregroundStyle(SurgeInk.tertiary(contrastLevel))
        }
    }
}
