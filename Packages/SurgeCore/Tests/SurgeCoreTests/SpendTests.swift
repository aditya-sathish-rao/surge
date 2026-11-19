import Foundation
import SurgeCore
import Testing

struct SpendTests {
    @Test func balanceDropIsSpend() throws {
        let movement = try #require(
            SpendAttribution.movement(provider: .deepseek, previousUSD: 12.40, currentUSD: 12.11)
        )

        #expect(movement.wasTopUp == false)
        #expect(movement.hasSpend)
        #expect(abs(movement.dropUSD - 0.29) < 0.000_001)
    }

    @Test func balanceIncreaseIsATopUpNotNegativeSpend() throws {
        let movement = try #require(
            SpendAttribution.movement(provider: .deepseek, previousUSD: 2.00, currentUSD: 22.00)
        )

        #expect(movement.wasTopUp)
        #expect(movement.hasSpend == false)
        #expect(movement.dropUSD == 0)
    }

    @Test func firstPollAndUnchangedBalanceReportNoMovement() {
        #expect(SpendAttribution.movement(provider: .deepseek, previousUSD: nil, currentUSD: 12.40) == nil)
        #expect(SpendAttribution.movement(provider: .deepseek, previousUSD: 12.40, currentUSD: nil) == nil)
        #expect(SpendAttribution.movement(provider: .deepseek, previousUSD: 12.40, currentUSD: 12.40) == nil)
    }

    @Test func topUpWindowAttributesNoSpend() {
        let movement = SpendAttribution.movement(provider: .deepseek, previousUSD: 2.00, currentUSD: 22.00)
        let shares = SpendAttribution.shares(
            dropUSD: movement?.hasSpend == true ? movement?.dropUSD ?? 0 : 0,
            tokensByAgent: ["worker-a": 4_000]
        )

        #expect(shares.isEmpty)
    }

    @Test func sharesSplitADropAcrossTheAgentsThatSpentIt() {
        let shares = SpendAttribution.shares(
            dropUSD: 0.60,
            tokensByAgent: ["worker-a": 2_000, "worker-b": 1_000]
        )

        #expect(abs((shares["worker-a"] ?? 0) - 0.40) < 0.000_001)
        #expect(abs((shares["worker-b"] ?? 0) - 0.20) < 0.000_001)
        #expect(abs(shares.values.reduce(0, +) - 0.60) < 0.000_001)
    }

    @Test func sharesIgnoreAgentsWithNoTokensAndStayEmptyWithoutATokenTotal() {
        let shares = SpendAttribution.shares(
            dropUSD: 0.60,
            tokensByAgent: ["worker-a": 1_000, "idle": 0]
        )

        #expect(shares["idle"] == nil)
        #expect(abs((shares["worker-a"] ?? 0) - 0.60) < 0.000_001)
        #expect(SpendAttribution.shares(dropUSD: 0.60, tokensByAgent: [:]).isEmpty)
    }

    @Test func spendingKeepsTheThreeSourcesApart() {
        var spend = SpendBySource()
        spend.add(0.10, source: .actual)
        spend.add(0.20, source: .derived)
        spend.add(0.30, source: .estimated)

        #expect(abs(spend.actualUSD - 0.10) < 0.000_001)
        #expect(abs(spend.derivedUSD - 0.20) < 0.000_001)
        #expect(abs(spend.estimatedUSD - 0.30) < 0.000_001)
        #expect(abs(spend.totalUSD - 0.60) < 0.000_001)
    }

    @Test func aTotalIsOnlyAsStrongAsItsWeakestPart() {
        var actualOnly = SpendBySource()
        actualOnly.add(1.00, source: .actual)
        #expect(actualOnly.source == .actual)

        var mixed = SpendBySource()
        mixed.add(1.00, source: .actual)
        mixed.add(0.50, source: .derived)
        #expect(mixed.source == .derived)

        mixed.add(0.25, source: .estimated)
        #expect(mixed.source == .estimated)
    }

    @Test func anEstimateCanBeTakenBackWhenAStrongerFigureReplacesIt() {
        var spend = SpendBySource()
        spend.add(0.20, source: .estimated)
        spend.removeEstimate(0.20)
        spend.add(0.11, source: .derived)

        #expect(abs(spend.estimatedUSD) < 0.000_001)
        #expect(abs(spend.totalUSD - 0.11) < 0.000_001)
        #expect(spend.source == .derived)
    }

    @Test func aFigureNeverPrintsItsNumberWithoutALabel() {
        for source in CostSource.allCases {
            let figure = SpendFigure(amountUSD: 1.42, source: source)
            #expect(figure.displayText.contains(source.suffix))
            #expect(figure.displayText.contains(figure.amountText))
            #expect(figure.accessibilityText.contains(source.label.lowercased()))
        }
    }

    @Test func anEmptyEstimateReadsAsAnEstimate() {
        let figure = SpendBySource().figure()

        #expect(figure.source == .estimated)
        #expect(figure.amountUSD == 0)
    }

    @Test func agentsWithoutACostFigureMakeTheWorkspaceUnavailable() {
        let known = AgentNode(
            id: "known",
            provider: "deepseek",
            modelName: "deepseek-chat",
            status: .working,
            estimatedCostUSD: 0.10,
            costSource: .derived,
            lastTokenAt: SurgeFixtures.referenceDate
        )
        let unknown = AgentNode(
            id: "unknown",
            provider: "openrouter",
            modelName: "mystery-model",
            status: .working,
            estimatedCostUSD: 0,
            costSource: nil,
            lastTokenAt: SurgeFixtures.referenceDate
        )

        let complete = WorkspaceSession(
            projectPath: "/Users/dev/code/surge",
            orchestrator: known,
            workers: []
        )
        #expect(complete.spendFigure?.source == .derived)
        #expect(complete.spendFigure?.amountUSD == 0.10)

        let partial = WorkspaceSession(
            projectPath: "/Users/dev/code/surge",
            orchestrator: known,
            workers: [unknown]
        )
        #expect(partial.spendFigure == nil)
    }
}
