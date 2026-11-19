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

    @Test func spendingKeepsTheFiveSourcesApart() {
        var spend = SpendBySource()
        spend.add(0.10, source: .providerReported)
        spend.add(0.20, source: .balanceDerived)
        spend.add(0.30, source: .estimated)
        spend.add(0.40, source: .harnessReported)
        spend.add(0.50, source: .quotaWindow)

        #expect(abs(spend.providerReportedUSD - 0.10) < 0.000_001)
        #expect(abs(spend.balanceDerivedUSD - 0.20) < 0.000_001)
        #expect(abs(spend.estimatedUSD - 0.30) < 0.000_001)
        #expect(abs(spend.harnessReportedUSD - 0.40) < 0.000_001)
        #expect(abs(spend.quotaWindowUSD - 0.50) < 0.000_001)
        #expect(abs(spend.totalUSD - 1.50) < 0.000_001)
        // Nothing can be booked as unavailable, so that case never enters a total.
        spend.add(1.00, source: .unavailable)
        #expect(abs(spend.totalUSD - 1.50) < 0.000_001)
    }

    @Test func aSnapshotNamesTheOldSourcesByTheirNewNames() throws {
        let legacy = #"{"amountUSD":1.42,"source":"actual"}"#
        let figure = try JSONDecoder().decode(SpendFigure.self, from: Data(legacy.utf8))
        #expect(figure.source == .providerReported)

        let derived = #"{"amountUSD":0.42,"source":"derived"}"#
        let other = try JSONDecoder().decode(SpendFigure.self, from: Data(derived.utf8))
        #expect(other.source == .balanceDerived)
    }

    @Test func aHarnessFigureOutranksALocalEstimateButNotAProviderBill() {
        let figures = TurnFigures(providerReportedUSD: 0.04, harnessReportedUSD: 0.06, estimateUSD: 0.05)
        let provider = BillingAccount.standard[2]
        let attributed = BillingAttribution.account(provider, basis: .binding)

        let booked = BillingResolver.book(figures, attribution: attributed)
        #expect(booked?.source == .providerReported)
        #expect(abs((booked?.amountUSD ?? 0) - 0.04) < 0.000_001)

        let harnessOnly = BillingResolver.book(
            TurnFigures(harnessReportedUSD: 0.06, estimateUSD: 0.05),
            attribution: attributed
        )
        #expect(harnessOnly?.source == .harnessReported)
    }

    @Test func aTotalIsOnlyAsStrongAsItsWeakestPart() {
        var providerOnly = SpendBySource()
        providerOnly.add(1.00, source: .providerReported)
        #expect(providerOnly.source == .providerReported)

        var mixed = SpendBySource()
        mixed.add(1.00, source: .providerReported)
        mixed.add(0.50, source: .balanceDerived)
        #expect(mixed.source == .balanceDerived)

        mixed.add(0.25, source: .estimated)
        #expect(mixed.source == .estimated)
    }

    @Test func anEstimateCanBeTakenBackWhenAStrongerFigureReplacesIt() {
        var spend = SpendBySource()
        spend.add(0.20, source: .estimated)
        spend.removeEstimate(0.20)
        spend.add(0.11, source: .balanceDerived)

        #expect(abs(spend.estimatedUSD) < 0.000_001)
        #expect(abs(spend.totalUSD - 0.11) < 0.000_001)
        #expect(spend.source == .balanceDerived)
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
            costSource: .balanceDerived,
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
        #expect(complete.spendFigure?.source == .balanceDerived)
        #expect(complete.spendFigure?.amountUSD == 0.10)

        let partial = WorkspaceSession(
            projectPath: "/Users/dev/code/surge",
            orchestrator: known,
            workers: [unknown]
        )
        #expect(partial.spendFigure == nil)
    }
}
