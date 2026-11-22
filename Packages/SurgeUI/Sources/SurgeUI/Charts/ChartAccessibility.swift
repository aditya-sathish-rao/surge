import Accessibility
import Foundation
import SurgeCore
import SwiftUI

/// One value in a chart as VoiceOver reads it: where it sits, what it is worth and what it is called.
public struct ChartDataPoint: Sendable, Equatable {
    /// Where the point sits on the chart's x axis.
    public enum Position: Sendable, Equatable {
        /// A date or a measurement on a numeric axis.
        case number(Double)
        /// A name on a categorical axis.
        case category(String)
    }

    public let position: Position
    public let value: Double
    /// A provider's share of today's spend, on the charts that draw a second axis for it.
    public let sharePercent: Double?

    public init(position: Position, value: Double, sharePercent: Double? = nil) {
        self.position = position
        self.value = value
        self.sharePercent = sharePercent
    }
}

/// One series of a chart: what it is called, whether it is continuous, and its points in order.
public struct ChartSeries: Sendable, Equatable {
    public let name: String
    public let isContinuous: Bool
    public let points: [ChartDataPoint]

    public init(name: String, isContinuous: Bool, points: [ChartDataPoint]) {
        self.name = name
        self.isContinuous = isContinuous
        self.points = points
    }
}

/// What VoiceOver reads for a chart: a spoken summary, then an `AXChartDescriptor` that lets a
/// reader walk the axes, the series and every value. The popover, the panel and the widget all
/// draw the same charts, so the wording and the descriptor are decided here once.
public enum ChartAccessibility {
    private static let locale = Locale(identifier: "en_US")

    // MARK: Wording

    /// "Mon, Jul 8". Shared by the axis and the spoken values so they always agree.
    public static func dayText(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone)
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
        )
    }

    /// "2:05 PM", the same shape the throughput axis draws.
    public static func timeText(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone)
                .hour()
                .minute()
        )
    }

    /// The last `range.dayCount` days, oldest first.
    public static func visibleDays(_ days: [DailySpendPoint], range: DailySpendRange) -> [DailySpendPoint] {
        Array(days.sorted { $0.date < $1.date }.suffix(range.dayCount))
    }

    // MARK: Daily spend

    public static func spendTitle(range: DailySpendRange) -> String {
        "Daily spend over \(range.dayCount) days"
    }

    /// "Today $1.42, estimated. $4.51, estimated over the last 6 days."
    public static func spendSummary(
        days: [DailySpendPoint],
        range: DailySpendRange,
        source: CostSource
    ) -> String {
        let visible = visibleDays(days, range: range)
        let total = visible.reduce(0) { $0 + $1.totalUSD }
        guard let last = visible.last, total > 0 else {
            return "No spend recorded in the last \(range.dayCount) days."
        }
        let today = SpendFigure(amountUSD: last.totalUSD, source: source).accessibilityText
        let window = SpendFigure(
            amountUSD: total,
            source: windowSource(source, dayCount: visible.count)
        ).accessibilityText
        let span = visible.count == 1 ? "today" : "over the last \(visible.count) days"
        return "Today \(today). \(window) \(span)."
    }

    /// One series per provider that has spend, each carrying that provider's days.
    public static func spendSeries(days: [DailySpendPoint], range: DailySpendRange) -> [ChartSeries] {
        let visible = visibleDays(days, range: range)
        return Provider.allCases.compactMap { provider in
            let points = visible.compactMap { day -> ChartDataPoint? in
                let amount = day.spend(for: provider)
                guard amount > 0 else { return nil }
                return ChartDataPoint(
                    position: .number(day.date.timeIntervalSinceReferenceDate),
                    value: amount
                )
            }
            guard !points.isEmpty else { return nil }
            return ChartSeries(name: provider.name, isContinuous: false, points: points)
        }
    }

    public static func spendDescriptor(
        days: [DailySpendPoint],
        range: DailySpendRange,
        source: CostSource = .estimated,
        timeZone: TimeZone = .current
    ) -> AXChartDescriptor {
        let visible = visibleDays(days, range: range)
        let positions = visible.map { $0.date.timeIntervalSinceReferenceDate }
        let first = positions.first ?? 0
        let last = max(positions.last ?? first, first + 86_400)
        let peak = visible.map(\.totalUSD).max() ?? 0
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Day",
            range: first...last,
            gridlinePositions: positions,
            valueDescriptionProvider: { value in
                dayText(Date(timeIntervalSinceReferenceDate: value), timeZone: timeZone)
            }
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Spend",
            range: 0...max(1, peak * 1.15),
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                SpendFigure(
                    amountUSD: value,
                    source: windowSource(source, dayCount: visible.count)
                ).accessibilityText
            }
        )
        return AXChartDescriptor(
            title: spendTitle(range: range),
            summary: spendSummary(days: days, range: range, source: source),
            xAxis: xAxis,
            yAxis: yAxis,
            series: seriesDescriptors(spendSeries(days: days, range: range))
        )
    }

    // MARK: Spend by provider

    /// "3 providers, $1.59, estimated today. Anthropic 64 percent, DeepSeek 26 percent."
    public static func shareSummary(shares: [SpendShare]) -> String {
        guard !shares.isEmpty else { return "No spend today." }
        let total = shares.reduce(0) { $0 + $1.amountUSD }
        let count = shares.count == 1 ? "One provider" : "\(shares.count) providers"
        let percents = shares.map { "\($0.provider.name) \($0.percent) percent" }.joined(separator: ", ")
        let figure = SpendFigure(amountUSD: total, source: shareSource(shares)).accessibilityText
        return "\(count), \(figure) today. \(percents)."
    }

    public static func shareSeries(shares: [SpendShare]) -> [ChartSeries] {
        guard !shares.isEmpty else { return [] }
        let points = shares.map { share in
            ChartDataPoint(
                position: .category(share.provider.name),
                value: share.amountUSD,
                sharePercent: Double(share.percent)
            )
        }
        return [ChartSeries(name: "Spend", isContinuous: false, points: points)]
    }

    public static func shareDescriptor(shares: [SpendShare]) -> AXChartDescriptor {
        let peak = shares.map(\.amountUSD).max() ?? 0
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Provider",
            categoryOrder: shares.map(\.provider.name)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Spend",
            range: 0...max(1, peak),
            gridlinePositions: [],
            valueDescriptionProvider: { value in
                SpendFigure(amountUSD: value, source: shareSource(shares)).accessibilityText
            }
        )
        let shareAxis = AXNumericDataAxisDescriptor(
            title: "Share",
            range: 0...100,
            gridlinePositions: [],
            valueDescriptionProvider: { "\(Int($0.rounded())) percent" }
        )
        return AXChartDescriptor(
            title: "Spend by provider today",
            summary: shareSummary(shares: shares),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [shareAxis],
            series: seriesDescriptors(shareSeries(shares: shares))
        )
    }

    // MARK: Throughput

    /// "Now 118 tok/s, 18% above your 30-minute average."
    public static func throughputSummary(samples: [ThroughputSample]) -> String {
        let summary = ThroughputSummary(samples: samples)
        guard summary.averageTokensPerSecond > 0 else {
            return "No tokens per second recorded in the last 30 minutes."
        }
        let caption = summary.caption.prefix(1).lowercased() + summary.caption.dropFirst()
        return "Now \(summary.headline), \(caption)."
    }

    public static func throughputSeries(samples: [ThroughputSample]) -> [ChartSeries] {
        let points = samples.sorted { $0.date < $1.date }.map { sample in
            ChartDataPoint(
                position: .number(sample.date.timeIntervalSinceReferenceDate),
                value: sample.tokensPerSecond
            )
        }
        guard !points.isEmpty else { return [] }
        return [ChartSeries(name: "Tokens per second", isContinuous: true, points: points)]
    }

    public static func throughputDescriptor(
        samples: [ThroughputSample],
        timeZone: TimeZone = .current
    ) -> AXChartDescriptor {
        let ordered = samples.sorted { $0.date < $1.date }
        let positions = ordered.map { $0.date.timeIntervalSinceReferenceDate }
        let first = positions.first ?? 0
        let last = max(positions.last ?? first, first + 60)
        let peak = ordered.map(\.tokensPerSecond).max() ?? 0
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: first...last,
            gridlinePositions: positions,
            valueDescriptionProvider: { value in
                timeText(Date(timeIntervalSinceReferenceDate: value), timeZone: timeZone)
            }
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Tokens per second",
            range: 0...max(1, peak * 1.15),
            gridlinePositions: [],
            valueDescriptionProvider: { value in "\(Int(value.rounded())) tokens per second" }
        )
        return AXChartDescriptor(
            title: "Throughput over the last 30 minutes",
            summary: throughputSummary(samples: samples),
            xAxis: xAxis,
            yAxis: yAxis,
            series: seriesDescriptors(throughputSeries(samples: samples))
        )
    }

    private static func seriesDescriptors(_ series: [ChartSeries]) -> [AXDataSeriesDescriptor] {
        series.map { series in
            AXDataSeriesDescriptor(
                name: series.name,
                isContinuous: series.isContinuous,
                dataPoints: series.points.map { point in
                    let extra = point.sharePercent.map { [AXDataPoint.Value.number($0)] } ?? []
                    switch point.position {
                    case .number(let value):
                        return AXDataPoint(x: value, y: point.value, additionalValues: extra)
                    case .category(let name):
                        return AXDataPoint(x: name, y: point.value, additionalValues: extra)
                    }
                }
            )
        }
    }

    /// A figure wider than today may never claim a stronger source than the ledger can prove: the
    /// days before today do not carry their own provenance into this boundary, and the ledger
    /// reads such history as an estimate.
    private static func windowSource(_ source: CostSource, dayCount: Int) -> CostSource {
        guard dayCount > 1 else { return source }
        return CostSource.weakest([source, .estimated]) ?? .estimated
    }

    /// The weakest source behind the shares, which is what the blended total can prove.
    private static func shareSource(_ shares: [SpendShare]) -> CostSource {
        CostSource.weakest(shares.map(\.source)) ?? .estimated
    }
}

/// The spend chart's data as VoiceOver reads it.
public struct DailySpendChartDescriptor: AXChartDescriptorRepresentable {
    private let days: [DailySpendPoint]
    private let range: DailySpendRange
    private let source: CostSource
    private let timeZone: TimeZone

    public init(
        days: [DailySpendPoint],
        range: DailySpendRange = .fourteenDays,
        source: CostSource = .estimated,
        timeZone: TimeZone = .current
    ) {
        self.days = days
        self.range = range
        self.source = source
        self.timeZone = timeZone
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        ChartAccessibility.spendDescriptor(days: days, range: range, source: source, timeZone: timeZone)
    }
}

/// The spend-by-provider bar as VoiceOver reads it.
public struct SpendByProviderChartDescriptor: AXChartDescriptorRepresentable {
    private let shares: [SpendShare]

    public init(shares: [SpendShare]) {
        self.shares = shares
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        ChartAccessibility.shareDescriptor(shares: shares)
    }
}

/// The throughput line as VoiceOver reads it.
public struct ThroughputChartDescriptor: AXChartDescriptorRepresentable {
    private let samples: [ThroughputSample]
    private let timeZone: TimeZone

    public init(samples: [ThroughputSample], timeZone: TimeZone = .current) {
        self.samples = samples
        self.timeZone = timeZone
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        ChartAccessibility.throughputDescriptor(samples: samples, timeZone: timeZone)
    }
}
