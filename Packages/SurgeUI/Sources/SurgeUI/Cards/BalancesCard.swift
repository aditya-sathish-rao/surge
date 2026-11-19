import SurgeCore
import SwiftUI

/// One account row's text. Balances are never summed across providers.
public struct BalancePresentation: Sendable, Equatable {
    public let provider: Provider
    public let providerName: String
    public let amountText: String
    /// Provider usage shown beside the amount, when the provider reports one.
    public let usageText: String?
    public let level: BalanceLevel?
    public let isUnavailable: Bool
    public let accessibilityLabel: String

    public init(balance: AccountBalance) {
        provider = balance.providerKind
        providerName = balance.providerKind.name
        isUnavailable = !balance.isAvailable
        usageText = balance.usageUSD.map { "used \(SurgeFormatting.cost($0))" }

        guard let amount = balance.amountUSD else {
            level = nil
            switch balance.kind {
            case .wallet:
                amountText = "Balance unavailable"
                accessibilityLabel = "\(providerName), balance unavailable"
            case .keyLimit:
                // The key has no cap, which is not the same as an empty account.
                amountText = "No key limit"
                accessibilityLabel = Self.keyLimitAccessibility(providerName, usage: balance.usageUSD)
            }
            return
        }

        let level = SurgeThresholds.balanceLevel(forUSD: amount)
        self.level = level
        let kindWord = balance.kind == .keyLimit ? "key cap" : "balance"
        amountText =
            balance.kind == .keyLimit
            ? "\(SurgeFormatting.cost(amount)) key cap"
            : SurgeFormatting.cost(amount)
        let usageWord = balance.usageUSD.map { ", used \(SurgeFormatting.cost($0))" } ?? ""
        accessibilityLabel =
            switch level {
            case .normal:
                "\(providerName), \(kindWord) \(SurgeFormatting.cost(amount))\(usageWord)"
            case .low:
                "\(providerName), \(kindWord) \(SurgeFormatting.cost(amount)), low\(usageWord)"
            case .empty:
                "\(providerName), \(kindWord) \(SurgeFormatting.cost(amount)), empty\(usageWord)"
            }
    }

    private static func keyLimitAccessibility(_ providerName: String, usage: Double?) -> String {
        guard let usage else { return "\(providerName), no key limit set" }
        return "\(providerName), no key limit set, used \(SurgeFormatting.cost(usage))"
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
            if let usageText = presentation.usageText {
                Text(usageText)
                    .font(SurgeUIFont.balanceCaption)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
                    .monospacedDigit()
            }
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
