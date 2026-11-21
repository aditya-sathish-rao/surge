import SurgeCore
import SwiftUI

/// One provider's part of the spend-by-provider bar: its amount, its share of the bar, and the
/// whole-number percentage in the legend. Shares always add up to 100 percent.
public struct SpendShare: Identifiable, Sendable, Equatable {
    public let provider: Provider
    public let amountUSD: Double
    public let fraction: Double
    public let percent: Int
    /// How the amount was obtained, so the label travels with the number.
    public let source: CostSource

    public var id: String { provider.rawValue }

    public var percentText: String { "\(percent)%" }

    public var figure: SpendFigure { SpendFigure(amountUSD: amountUSD, source: source) }

    public var amountText: String { figure.displayText }

    public var accessibilityLabel: String {
        "\(provider.name), \(figure.accessibilityText), \(percent) percent"
    }
}

public enum SpendShares {
    /// Providers with no spend are left out. Percentages use largest-remainder rounding so they
    /// always total 100.
    public static func make(for day: DailySpendPoint, source: CostSource = .estimated) -> [SpendShare] {
        let amounts = Provider.allCases.map { ($0, max(day.spend(for: $0), 0)) }.filter { $0.1 > 0 }
        let total = amounts.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        let raw = amounts.map { ($0.0, $0.1 / total * 100) }
        var percents = raw.map { Int($0.1) }
        var remainder = 100 - percents.reduce(0, +)
        let order = raw.indices.sorted { left, right in
            let leftFraction = raw[left].1 - Double(percents[left])
            let rightFraction = raw[right].1 - Double(percents[right])
            return leftFraction == rightFraction ? left < right : leftFraction > rightFraction
        }
        for index in order where remainder > 0 {
            percents[index] += 1
            remainder -= 1
        }
        return amounts.indices.map { index in
            let (provider, amount) = amounts[index]
            return SpendShare(
                provider: provider,
                amountUSD: amount,
                fraction: amount / total,
                percent: percents[index],
                source: source
            )
        }
    }
}

/// A proportional bar with 1.5 pt separators and a legend of dot, name, amount and share.
public struct SpendByProviderBar: View {
    private let shares: [SpendShare]
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(shares: [SpendShare]) {
        self.shares = shares
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
            SurgeSectionLabel("Spend by provider · today")
            if shares.isEmpty {
                // A card with only a heading reads as broken. Say the day is empty instead.
                Text("No spend today")
                    .font(SurgeUIFont.rowMeta)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
            } else {
                bar
                VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
                    ForEach(shares) { share in
                        legendRow(share)
                    }
                }
            }
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let gapTotal = SurgeUIStyle.chartBarGap * CGFloat(max(shares.count - 1, 0))
            let available = max(proxy.size.width - gapTotal, 0)
            HStack(spacing: SurgeUIStyle.chartBarGap) {
                ForEach(shares) { share in
                    RoundedRectangle(cornerRadius: SurgeUIStyle.proportionalBarRadius)
                        .fill(share.provider.color)
                        .frame(width: max(available * CGFloat(share.fraction), 2))
                }
            }
        }
        .frame(height: SurgeUIStyle.proportionalBarHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(barAccessibilityLabel)
        .accessibilityChartDescriptor(SpendByProviderChartDescriptor(shares: shares))
    }

    private func legendRow(_ share: SpendShare) -> some View {
        HStack(spacing: SurgeSpacing.space1) {
            ProviderDot(provider: share.provider, size: SurgeUIStyle.legendDotSize)
            Text(share.provider.name)
                .font(SurgeUIFont.rowMeta)
                .foregroundStyle(SurgeInk.primary())
            Spacer(minLength: SurgeSpacing.space2)
            Text(share.amountText)
                .font(SurgeUIFont.rowMeta)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
                .monospacedDigit()
            Text(share.percentText)
                .font(SurgeUIFont.rowMeta)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
                .monospacedDigit()
                .frame(width: SurgeUIStyle.percentColumnWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(share.accessibilityLabel)
    }

    private var barAccessibilityLabel: String {
        ChartAccessibility.shareSummary(shares: shares)
    }
}
