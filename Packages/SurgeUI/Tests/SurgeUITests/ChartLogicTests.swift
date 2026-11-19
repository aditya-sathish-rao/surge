import Foundation
import SurgeCore
import Testing

@testable import SurgeUI

struct ChartLogicTests {
    @Test func throughputSummaryComparesToTheAverage() {
        let above = ThroughputSummary(samples: samples([82, 100, 118]))
        #expect(above.headline == "118 tok/s")
        #expect(above.caption == "18% above your 30-minute average")

        let below = ThroughputSummary(samples: samples([118, 100, 82]))
        #expect(below.caption == "18% below your 30-minute average")

        let level = ThroughputSummary(samples: samples([100, 100, 100]))
        #expect(level.caption == "In line with your 30-minute average")
        #expect(level.headline == "100 tok/s")
    }

    @Test func throughputSummaryHandlesNoSamples() {
        let empty = ThroughputSummary(samples: [])

        #expect(empty.headline == "0 tok/s")
        #expect(empty.caption == "No throughput yet")
        #expect(empty.averageTokensPerSecond == 0)
    }

    @Test func throughputSummaryAveragesEverySample() {
        let summary = ThroughputSummary(samples: samples([60, 120, 180]))

        #expect(summary.currentTokensPerSecond == 180)
        #expect(summary.averageTokensPerSecond == 120)
    }

    @Test func spendSharesAlwaysAddUpToHundred() {
        let day = DailySpendPoint(
            date: UITestFixtures.now,
            spendByProvider: ["anthropic": 1.02, "deepseek": 0.42, "openrouter": 0.15]
        )
        let shares = SpendShares.make(for: day)

        #expect(shares.map(\.provider) == [.anthropic, .deepseek, .openrouter])
        #expect(shares.map(\.percent) == [64, 26, 10])
        #expect(shares.map(\.percent).reduce(0, +) == 100)
        #expect(shares.map(\.percentText) == ["64%", "26%", "10%"])
        #expect(shares.map(\.amountText) == ["$1.02 est.", "$0.42 est.", "$0.15 est."])
        #expect(abs(shares.map(\.fraction).reduce(0, +) - 1) < 0.000_001)
    }

    @Test func aThreeWayTieIsBrokenInProviderOrder() {
        let day = DailySpendPoint(
            date: UITestFixtures.now,
            spendByProvider: ["anthropic": 0.42, "deepseek": 0.18, "openrouter": 0.05]
        )

        #expect(SpendShares.make(for: day).map(\.percent) == [64, 28, 8])
    }

    @Test func providersWithNoSpendStayOutOfTheBar() {
        let day = DailySpendPoint(date: UITestFixtures.now, spendByProvider: ["deepseek": 2])
        let shares = SpendShares.make(for: day)

        #expect(shares.count == 1)
        #expect(shares[0].provider == .deepseek)
        #expect(shares[0].percent == 100)
        #expect(shares[0].fraction == 1)
        #expect(shares[0].accessibilityLabel == "DeepSeek, $2.00, estimated, 100 percent")
    }

    @Test func aDayWithNoSpendHasNoShares() {
        let day = DailySpendPoint(date: UITestFixtures.now, spendByProvider: [:])

        #expect(SpendShares.make(for: day).isEmpty)
    }

    @Test func aShareCarriesTheSourceItWasGiven() {
        let day = DailySpendPoint(date: UITestFixtures.now, spendByProvider: ["openrouter": 0.40])
        let shares = SpendShares.make(for: day, source: .actual)

        #expect(shares[0].amountText == "$0.40 actual")
        #expect(shares[0].accessibilityLabel == "OpenRouter, $0.40, actual, 100 percent")
    }

    @Test func theChartHeadlineCarriesItsLabel() {
        #expect(DailySpendChart.headline(todayUSD: 1.42, source: .estimated) == "$1.42 est. today")
        #expect(DailySpendChart.headline(todayUSD: 0, source: .derived) == "$0.00 derived today")
        #expect(DailySpendChart.headline(todayUSD: 2.00, source: .actual) == "$2.00 actual today")
    }

    @Test func dailySpendRangeCarriesItsTitleAndLength() {
        #expect(DailySpendRange.sevenDays.dayCount == 7)
        #expect(DailySpendRange.fourteenDays.dayCount == 14)
        #expect(DailySpendRange.sevenDays.title == "Daily spend · 7 days")
        #expect(DailySpendRange.fourteenDays.title == "Daily spend · 14 days")
    }

    @Test func tokenCountsReadTheSameOnEveryMachine() {
        #expect(TokenCountFormat.text(0) == "0")
        #expect(TokenCountFormat.text(9_000) == "9K")
        #expect(TokenCountFormat.text(8_800) == "8.8K")
        #expect(TokenCountFormat.text(152_000) == "152K")
        #expect(TokenCountFormat.text(1_200_000) == "1.2M")
        #expect(TokenCountFormat.text(-5) == "0")
    }

    @Test func tokenTotalsKeepTheAgentOrder() {
        let totals = AgentTokenTotals.make(for: SurgeFixtures.workspaces)

        #expect(totals.count == 7)
        #expect(totals[0].modelName == "Claude Sonnet")
        #expect(totals[0].isSubAgent == false)
        #expect(totals[1].isSubAgent)
        #expect(totals[0].inputTokens == 42_000)
        #expect(totals[0].cacheHitTokens == 152_000)
        #expect(totals[0].provider == .anthropic)
    }

    private func samples(_ values: [Double]) -> [ThroughputSample] {
        values.enumerated().map { index, value in
            ThroughputSample(
                date: UITestFixtures.now.addingTimeInterval(TimeInterval(index * 60)),
                tokensPerSecond: value
            )
        }
    }
}
