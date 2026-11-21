import Foundation
import SurgeCore
import Testing

@testable import SurgeWidgetLogic

struct WidgetSpendChartTests {
    /// Fixed calendar and region so the labels a test asserts cannot move with the machine.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    private static let locale = Locale(identifier: "en_US")

    private static func days(_ points: [DailySpendPoint]) -> [WidgetSpendChart.Day] {
        WidgetSpendChart.days(in: points, calendar: calendar, locale: locale)
    }

    @Test func theDescriptorCoversTheSameSevenDaysTheChartDraws() {
        let days = Self.days(SurgeFixtures.dailySpend)

        #expect(days.count == WidgetSpendChart.dayCount)
        #expect(days.map(\.label) == ["Nov 7", "Nov 8", "Nov 9", "Nov 10", "Nov 11", "Nov 12", "Nov 13"])
    }

    @Test func theOldestDaysFallAwaySoTheNewestStayOnScreen() {
        let extra = DailySpendPoint(date: Self.date(daysAgo: 30), spendByProvider: ["anthropic": 9.99])
        let days = Self.days(SurgeFixtures.dailySpend + [extra])

        #expect(days.count == WidgetSpendChart.dayCount)
        #expect(days.last?.label == "Nov 13")
        #expect(days.contains { $0.amountUSD == 9.99 } == false)
    }

    @Test func aDayCarriesEveryProviderDrawnOnIt() {
        let days = Self.days(SurgeFixtures.dailySpend)

        // SurgeFixtures' last day is 0.83 Anthropic, 0.28 DeepSeek and 0.11 OpenRouter.
        #expect(days.last?.amountUSD == 1.22)
    }

    @Test func theSummaryNamesTodaysAmountTheTotalAndHowItWasPriced() {
        let days = Self.days(SurgeFixtures.dailySpend)

        let summary = WidgetSpendChart.summary(days, source: .estimated)

        #expect(summary == "Estimated daily spend for the last 7 days. $1.22 today, $7.08 in total.")
    }

    @Test func aChartWithNothingToDrawSaysSoInsteadOfReadingZeroDollars() {
        let summary = WidgetSpendChart.summary([], source: .estimated)

        #expect(summary == "No daily spend recorded in the last 7 days.")
    }

    @Test func theValueAxisAlwaysHasARangeWorthReading() {
        let none: [WidgetSpendChart.Day] = []

        #expect(WidgetSpendChart.valueAxisMaximum(none) == 1)
        #expect(WidgetSpendChart.valueAxisMaximum([.init(label: "Nov 7", amountUSD: 0.4)]) == 1)
        #expect(WidgetSpendChart.valueAxisMaximum([.init(label: "Nov 7", amountUSD: 2.5)]) == 2.5)
    }

    @Test func anAxisLabelIsTheMonthAndDayInTheRegionsOrder() {
        let date = Self.date(daysAgo: 0)

        #expect(
            WidgetSpendChart.label(for: date, calendar: Self.calendar, locale: Self.locale) == "Nov 13"
        )
        #expect(
            WidgetSpendChart.label(for: date, calendar: Self.calendar, locale: Locale(identifier: "en_GB"))
                == "13 Nov"
        )
    }

    private static func date(daysAgo: Int) -> Date {
        SurgeFixtures.referenceDate.addingTimeInterval(-Double(daysAgo) * 86_400)
    }
}
