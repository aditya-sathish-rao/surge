import Charts
import SurgeCore
import SwiftUI

/// How many days the spend chart covers: 14 in the popover, 7 in the Large widget.
public enum DailySpendRange: Sendable, Equatable {
    case sevenDays
    case fourteenDays

    public var dayCount: Int {
        switch self {
        case .sevenDays: 7
        case .fourteenDays: 14
        }
    }

    public var title: String {
        "Daily spend · \(dayCount) days"
    }
}

/// The daily spend chart: thin rounded stacked bars, today at full opacity and earlier days at 70 percent.
public struct DailySpendChart: View {
    private let days: [DailySpendPoint]
    private let range: DailySpendRange
    private let isWidget: Bool
    /// How today's amount was obtained. The chart never prints a number without it.
    private let source: CostSource
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(
        days: [DailySpendPoint],
        range: DailySpendRange = .fourteenDays,
        isWidget: Bool = false,
        source: CostSource = .estimated
    ) {
        self.days = days
        self.range = range
        self.isWidget = isWidget
        self.source = source
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            SurgeSectionLabel(range.title, isWidget: isWidget)
            Text(todayHeadline)
                .font(isWidget ? SurgeUIFont.chartHeadlineCompact : SurgeUIFont.chartHeadline)
                .foregroundStyle(SurgeInk.primary())
                .monospacedDigit()
            chart
        }
    }

    private var visibleDays: [DailySpendPoint] {
        ChartAccessibility.visibleDays(days, range: range)
    }

    private var todayHeadline: String {
        Self.headline(todayUSD: visibleDays.last?.totalUSD ?? 0, source: source)
    }

    /// The headline always carries the label its number earned.
    public static func headline(todayUSD: Double, source: CostSource) -> String {
        "\(SpendFigure(amountUSD: todayUSD, source: source).displayText) today"
    }

    private var chart: some View {
        Chart {
            ForEach(visibleDays) { day in
                ForEach(Provider.allCases, id: \.self) { provider in
                    let amount = day.spend(for: provider)
                    if amount > 0 {
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Spend", amount),
                            width: .fixed(SurgeUIStyle.chartBarWidth)
                        )
                        .foregroundStyle(by: .value("Provider", provider.name))
                        .cornerRadius(SurgeUIStyle.chartCornerRadius)
                        .opacity(isToday(day) ? SurgeUIStyle.chartTodayOpacity : SurgeUIStyle.chartPastOpacity)
                    }
                }
            }
        }
        .chartForegroundStyleScale(
            domain: Provider.allCases.map(\.name),
            range: Provider.allCases.map(\.color)
        )
        .chartLegend(.hidden)
        .chartYScale(domain: 0...max(1, (visibleDays.map(\.totalUSD).max() ?? 0) * 1.15))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(SurgeInk.primary().opacity(SurgeUIStyle.chartGridOpacity))
                AxisValueLabel()
                    .font(isWidget ? SurgeUIFont.chartAxisWidget : SurgeUIFont.chartAxis)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisTick().foregroundStyle(SurgeInk.primary().opacity(SurgeUIStyle.chartTickOpacity))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(isWidget ? SurgeUIFont.chartAxisWidget : SurgeUIFont.chartAxis)
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
            }
        }
        .frame(height: SurgeUIStyle.spendChartHeight)
        .accessibilityLabel(ChartAccessibility.spendTitle(range: range))
        .accessibilityChartDescriptor(
            DailySpendChartDescriptor(days: visibleDays, range: range, source: source)
        )
    }

    private func isToday(_ day: DailySpendPoint) -> Bool {
        day.id == visibleDays.last?.id
    }
}
