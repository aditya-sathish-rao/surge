import Accessibility
import Foundation
import SurgeCore
import Testing

@testable import SurgeUI

struct ChartAccessibilityTests {
    private let utc = TimeZone(identifier: "UTC") ?? .gmt

    @Test func theSpendSummaryNamesTodayAndTheWholeWindow() {
        let summary = ChartAccessibility.spendSummary(
            days: SurgeFixtures.dailySpend,
            range: .sevenDays,
            source: .estimated
        )

        #expect(summary == "Today $1.22, estimated. $7.08 over the last 7 days.")
    }

    @Test func anEmptySpendWindowSaysSo() {
        #expect(
            ChartAccessibility.spendSummary(days: [], range: .fourteenDays, source: .estimated)
                == "No spend recorded in the last 14 days."
        )

        let emptyDay = DailySpendPoint(date: UITestFixtures.now, spendByProvider: [:])
        #expect(
            ChartAccessibility.spendSummary(days: [emptyDay], range: .sevenDays, source: .estimated)
                == "No spend recorded in the last 7 days."
        )
    }

    @Test func theSpendSummaryCarriesTheSourceOfTodaysFigure() {
        let summary = ChartAccessibility.spendSummary(
            days: SurgeFixtures.dailySpend,
            range: .sevenDays,
            source: .providerReported
        )

        #expect(summary == "Today $1.22, provider reported. $7.08 over the last 7 days.")
    }

    @Test func theSpendChartHasOneSeriesPerProviderWithItsDays() {
        let series = ChartAccessibility.spendSeries(days: SurgeFixtures.dailySpend, range: .sevenDays)

        #expect(series.map(\.name) == ["Anthropic", "DeepSeek", "OpenRouter"])
        #expect(series.allSatisfy { !$0.isContinuous })
        #expect(series[0].points.count == 7)
        // OpenRouter spent nothing on day 3, so that provider has no point for it.
        #expect(series[2].points.count == 6)
        #expect(series[1].points.last?.value == 0.28)
        #expect(series.map(\.points.last?.position) == [day(0), day(0), day(0)])
        #expect(series[1].points.count == 7)
        #expect(series[1].points.first?.position == day(-6))
        #expect(series[1].points.last?.position == day(0))
    }

    @Test func aSevenDayRangeKeepsOnlyTheLastSevenDays() {
        let long = (0..<20).map { index in
            DailySpendPoint(
                date: UITestFixtures.now.addingTimeInterval(Double(index - 19) * 86_400),
                spendByProvider: ["anthropic": 0.10]
            )
        }

        let series = ChartAccessibility.spendSeries(days: long, range: .sevenDays)

        #expect(series[0].points.count == 7)
        #expect(series[0].points.first?.value == 0.10)
        #expect(series[0].points.first?.position == day(-6))
    }

    @Test func theSpendDescriptorCarriesItsTitleSummaryAndAxes() throws {
        let descriptor = ChartAccessibility.spendDescriptor(
            days: SurgeFixtures.dailySpend,
            range: .sevenDays,
            source: .estimated,
            timeZone: utc
        )

        #expect(descriptor.title == "Daily spend over 7 days")
        #expect(descriptor.summary == "Today $1.22, estimated. $7.08 over the last 7 days.")

        let xAxis = try #require(descriptor.xAxis as? AXNumericDataAxisDescriptor)
        #expect(xAxis.title == "Day")
        #expect(xAxis.gridlinePositions.count == 7)
        #expect(xAxis.valueDescriptionProvider(xAxis.gridlinePositions[0]) == "Fri, Nov 7")

        let yAxis = try #require(descriptor.yAxis)
        #expect(yAxis.title == "Spend")
        #expect(yAxis.range.lowerBound == 0)
        #expect(yAxis.valueDescriptionProvider(1.42) == "$1.42")
        #expect(descriptor.series.map(\.name) == ["Anthropic", "DeepSeek", "OpenRouter"])
    }

    @Test func theShareSummaryCountsProvidersAndTheirPercentages() {
        let day = DailySpendPoint(
            date: UITestFixtures.now,
            spendByProvider: ["anthropic": 1.02, "deepseek": 0.42, "openrouter": 0.15]
        )

        #expect(
            ChartAccessibility.shareSummary(shares: SpendShares.make(for: day))
                == "3 providers, $1.59 today. Anthropic 64 percent, DeepSeek 26 percent, OpenRouter 10 percent."
        )
        #expect(ChartAccessibility.shareSummary(shares: []) == "No spend today.")
    }

    @Test func oneProviderReadsAsSingular() {
        let day = DailySpendPoint(date: UITestFixtures.now, spendByProvider: ["deepseek": 2])

        #expect(
            ChartAccessibility.shareSummary(shares: SpendShares.make(for: day))
                == "One provider, $2.00 today. DeepSeek 100 percent."
        )
    }

    @Test func theShareChartKeepsTheProviderOrderAndTheShareOfEach() {
        let day = DailySpendPoint(
            date: UITestFixtures.now,
            spendByProvider: ["anthropic": 1.02, "deepseek": 0.42, "openrouter": 0.15]
        )
        let shares = SpendShares.make(for: day)
        let series = ChartAccessibility.shareSeries(shares: shares)

        #expect(series.count == 1)
        #expect(series[0].name == "Spend")
        #expect(
            series[0].points.map(\.position)
                == [.category("Anthropic"), .category("DeepSeek"), .category("OpenRouter")]
        )
        #expect(series[0].points.map(\.value) == [1.02, 0.42, 0.15])
        #expect(series[0].points.map(\.sharePercent) == [64, 26, 10])

        let descriptor = ChartAccessibility.shareDescriptor(shares: shares)
        let xAxis = descriptor.xAxis as? AXCategoricalDataAxisDescriptor
        #expect(xAxis?.title == "Provider")
        #expect(xAxis?.categoryOrder == ["Anthropic", "DeepSeek", "OpenRouter"])
        #expect(descriptor.additionalAxes.count == 1)
        #expect(descriptor.title == "Spend by provider today")
    }

    @Test func anEmptyProviderBarHasNoSeries() {
        let descriptor = ChartAccessibility.shareDescriptor(shares: [])

        #expect(descriptor.summary == "No spend today.")
        #expect(descriptor.series.isEmpty)
    }

    @Test func theThroughputSummaryReadsTheCurrentRateAgainstTheAverage() {
        let above = ChartAccessibility.throughputSummary(samples: samples([82, 100, 118]))
        #expect(above == "Now 118 tok/s, 18% above your 30-minute average.")

        let level = ChartAccessibility.throughputSummary(samples: samples([100, 100, 100]))
        #expect(level == "Now 100 tok/s, in line with your 30-minute average.")
    }

    @Test func noThroughputSaysSo() {
        #expect(
            ChartAccessibility.throughputSummary(samples: [])
                == "No tokens per second recorded in the last 30 minutes."
        )
    }

    @Test func theThroughputChartIsOneContinuousSeriesOfSamples() {
        let series = ChartAccessibility.throughputSeries(samples: samples([60, 120, 180]))

        #expect(series.count == 1)
        #expect(series[0].isContinuous)
        #expect(series[0].name == "Tokens per second")
        #expect(series[0].points.map(\.value) == [60, 120, 180])
        #expect(series[0].points.map(\.position) == samplePositions(count: 3))
    }

    @Test func theSpokenTimesAreTheSameOnEveryMachine() {
        let start = Date(timeIntervalSince1970: 1_762_770_600)

        // ICU puts a narrow no-break space before AM and PM, so compare on plain spaces.
        #expect(
            ChartAccessibility.timeText(start, timeZone: utc)
                .replacingOccurrences(of: "\u{202F}", with: " ") == "10:30 AM"
        )
        #expect(ChartAccessibility.dayText(start, timeZone: utc) == "Mon, Nov 10")
    }

    @Test func theThroughputDescriptorCarriesItsAxesAndSummary() throws {
        let descriptor = ChartAccessibility.throughputDescriptor(samples: samples([60, 120, 180]), timeZone: utc)
        let yAxis = try #require(descriptor.yAxis)

        #expect(descriptor.title == "Throughput over the last 30 minutes")
        #expect(descriptor.summary == "Now 180 tok/s, 50% above your 30-minute average.")
        #expect(yAxis.title == "Tokens per second")
        #expect(yAxis.valueDescriptionProvider(68) == "68 tokens per second")
        #expect(descriptor.series.first?.dataPoints.count == 3)
    }

    private func day(_ offsetFromToday: Int) -> ChartDataPoint.Position {
        .number(UITestFixtures.now.addingTimeInterval(Double(offsetFromToday) * 86_400).timeIntervalSinceReferenceDate)
    }

    private func samplePositions(count: Int) -> [ChartDataPoint.Position] {
        let start = Date(timeIntervalSince1970: 1_762_770_600)
        return (0..<count).map { index in
            .number(start.addingTimeInterval(TimeInterval(index * 60)).timeIntervalSinceReferenceDate)
        }
    }

    private func samples(_ values: [Double]) -> [ThroughputSample] {
        // 2025-11-10 10:30 UTC, so the spoken times do not depend on the machine.
        let start = Date(timeIntervalSince1970: 1_762_770_600)
        return values.enumerated().map { index, value in
            ThroughputSample(
                date: start.addingTimeInterval(TimeInterval(index * 60)),
                tokensPerSecond: value
            )
        }
    }
}
