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
    /// Why the balance is missing, in plain English. Nil when having no amount is expected, such
    /// as a provider that exposes no balance endpoint.
    public let reasonText: String?
    /// The burn and reset line a subscription window shows instead of a balance.
    public let quotaText: String?
    /// How much of the window has been used. Nil for a wallet.
    public let quotaFraction: Double?
    public let accessibilityLabel: String

    public init(balance: AccountBalance, now: Date = Date()) {
        provider = balance.providerKind
        if let window = balance.quotaWindow {
            let quota = Self.quota(window, now: now)
            providerName = window.window.title
            amountText = quota.amountText
            quotaText = quota.detail
            quotaFraction = window.fractionUsed
            level = quota.level
            isUnavailable = false
            usageText = nil
            reasonText = nil
            accessibilityLabel = quota.accessibilityLabel
            return
        }
        providerName = balance.providerKind.name
        isUnavailable = !balance.isAvailable
        usageText = balance.usageUSD.map { "used \(SurgeFormatting.cost($0))" }
        quotaText = nil
        quotaFraction = nil

        guard let amount = balance.amountUSD else {
            level = nil
            reasonText = balance.unavailableReason?.text
            amountText =
                balance.kind == .keyLimit && balance.unavailableReason == nil
                ? "No key limit"
                : "Balance unavailable"
            accessibilityLabel = Self.unavailableAccessibility(for: balance)
            return
        }

        reasonText = nil
        let level = SurgeThresholds.balanceLevel(forUSD: amount)
        self.level = level
        amountText =
            balance.kind == .keyLimit ? "\(SurgeFormatting.cost(amount)) key cap" : SurgeFormatting.cost(amount)
        accessibilityLabel = Self.amountAccessibility(for: balance, level: level)
    }

    private struct QuotaText {
        let amountText: String
        let detail: String
        let level: BalanceLevel
        let accessibilityLabel: String
    }

    private static func quota(_ window: QuotaWindowState, now: Date) -> QuotaText {
        let remaining = window.remainingSeconds(at: now)
        let reset =
            remaining <= 0 ? "resets now" : "resets in \(SurgeFormatting.duration(since: now, now: window.resetsAt))"
        // Headroom is what runs out, so the balance thresholds applied to it keep Low and Empty
        // meaning the same thing as on a wallet.
        let level: BalanceLevel =
            window.isOverWindow ? .empty : (window.percentUsed >= 80 ? .low : .normal)
        let amount =
            "\(SurgeFormatting.cost(window.usedUSD)) of \(SurgeFormatting.cost(window.window.limitUSD))"
        let percent = "\(window.percentUsed)% used · \(reset)"
        let spoken =
            "\(window.window.title), quota window, \(amount) used, "
            + "\(window.percentUsed) percent of the window, \(reset)"
        return QuotaText(amountText: amount, detail: percent, level: level, accessibilityLabel: spoken)
    }

    private static func unavailableAccessibility(for balance: AccountBalance) -> String {
        let name = balance.providerKind.name
        if balance.kind == .keyLimit, let reason = balance.unavailableReason {
            return "\(name), balance unavailable. \(reason.text)."
        }
        if balance.kind == .keyLimit, balance.unavailableReason == nil {
            return keyLimitAccessibility(name, usage: balance.usageUSD)
        }
        guard let reason = balance.unavailableReason else { return "\(name), balance unavailable" }
        return "\(name), balance unavailable. \(reason.text)."
    }

    private static func amountAccessibility(for balance: AccountBalance, level: BalanceLevel) -> String {
        let name = balance.providerKind.name
        let amount = SurgeFormatting.cost(balance.amountUSD ?? 0)
        let word = balance.kind == .keyLimit ? "key cap" : "balance"
        let usage = balance.usageUSD.map { ", used \(SurgeFormatting.cost($0))" } ?? ""
        switch level {
        case .normal: return "\(name), \(word) \(amount)\(usage)"
        case .low: return "\(name), \(word) \(amount), low\(usage)"
        case .empty: return "\(name), \(word) \(amount), empty\(usage)"
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
        case .empty: quotaFraction == nil ? "Empty" : "At limit"
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
                    row(BalancePresentation(balance: balance, now: now))
                }
                caption
            }
        }
    }

    private func row(_ presentation: BalancePresentation) -> some View {
        HStack(spacing: SurgeSpacing.space1) {
            ProviderDot(provider: presentation.provider)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: SurgeSpacing.space1) {
                    Text(presentation.providerName)
                        .font(SurgeUIFont.balanceName)
                        .foregroundStyle(SurgeInk.primary())
                    if let qualifier = presentation.qualifier {
                        Text(qualifier)
                            .font(SurgeUIFont.balanceQualifier)
                            .foregroundStyle(presentation.qualifierColor ?? SurgeInk.secondary(contrastLevel))
                    }
                }
                if let reasonText = presentation.reasonText {
                    Text(reasonText)
                        .font(SurgeUIFont.balanceReason)
                        .foregroundStyle(SurgeInk.secondary(contrastLevel))
                }
                if let quotaText = presentation.quotaText {
                    Text(quotaText)
                        .font(SurgeUIFont.balanceReason)
                        .foregroundStyle(SurgeInk.secondary(contrastLevel))
                        .monospacedDigit()
                }
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
