import Accessibility
import SurgeCore
import SwiftUI

/// Makes the Large widget's 7-day spend chart readable by VoiceOver and Audio Graphs: one series,
/// one point per drawn day, and the same wording the rest of the widget uses.
struct WidgetSpendChartDescriptor: AXChartDescriptorRepresentable {
    private let days: [WidgetSpendChart.Day]

    /// The chart always draws its numbers as local estimates, so the spoken summary says so too.
    init(days points: [DailySpendPoint], source: CostSource = .estimated) {
        days = WidgetSpendChart.days(in: points)
        summary = WidgetSpendChart.summary(days, source: source)
    }

    private let summary: String

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: WidgetSpendChart.axisTitle,
            categoryOrder: days.map(\.label)
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: WidgetSpendChart.valueAxisTitle,
            range: 0...WidgetSpendChart.valueAxisMaximum(days),
            gridlinePositions: []
        ) { value in
            SurgeFormatting.cost(value)
        }
        let series = AXDataSeriesDescriptor(
            name: WidgetSpendChart.seriesName,
            isContinuous: false,
            dataPoints: days.map { day in
                AXDataPoint(x: day.label, y: day.amountUSD)
            }
        )
        return AXChartDescriptor(
            title: WidgetSpendChart.title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
