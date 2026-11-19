import Foundation
import SurgeCore
import Testing

@Suite("Daily spend ledger")
struct SpendLedgerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private var now: Date { calendar.startOfDay(for: SurgeFixtures.referenceDate).addingTimeInterval(12 * 3600) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now) ?? now
    }

    private func agent(
        _ id: String,
        provider: String,
        cost: Double,
        source: CostSource?,
        account: String? = "deepseek",
        harness: HarnessIdentity? = nil
    ) -> AgentNode {
        AgentNode(
            id: id,
            provider: provider,
            modelName: "deepseek-flash",
            status: .working,
            estimatedCostUSD: cost,
            costSource: source,
            lastTokenAt: now,
            harness: harness,
            billingAccount: account.flatMap { id in BillingAccount.standard.first { $0.id == id } }
        )
    }

    private func workspace(_ agents: [AgentNode]) -> WorkspaceSession {
        WorkspaceSession(
            projectPath: "/Users/dev/code/surge",
            orchestrator: agents[0],
            workers: Array(agents.dropFirst())
        )
    }

    private func balance(_ provider: String, _ amount: Double) -> AccountBalance {
        AccountBalance(provider: provider, amountUSD: amount, lastPolledAt: now)
    }

    private var delta: Double { 0.000_001 }

    @Test func spendIsGroupedByProviderFamilyAndNeverByHarnessName() {
        var ledger = DailySpendLedger(calendar: calendar)
        let piTurn = agent(
            "session-pi",
            provider: "pi",
            cost: 0.02,
            source: .harnessReported,
            harness: HarnessIdentity(kind: .piAgent, sessionID: "session-pi", transport: .jsonl)
        )

        ledger.record(workspaces: [workspace([piTurn])], at: now)

        let point = ledger.todayPoint(at: now)
        // The account that pays decides the family. "pi" is the harness, not a provider.
        #expect(abs(point.spend(for: .deepseek) - 0.02) < delta)
        #expect(point.spendByProvider["pi"] == nil)
        #expect(abs(ledger.todayTotal(at: now) - 0.02) < delta)
        #expect(ledger.todaySource(at: now) == .harnessReported)
    }

    @Test func anUnexplainedBalanceDropSurfacesAsBalanceDerived() {
        let seed = SurgeSnapshot(
            generatedAt: now.addingTimeInterval(-600),
            workspaces: [],
            balances: [balance("deepseek", 12.40)],
            dailySpend: []
        )
        var ledger = DailySpendLedger(seed: seed, calendar: calendar)

        // Nothing Surge saw spent the money, but the provider's balance moved by 0.58.
        ledger.record(workspaces: [], balances: [balance("deepseek", 11.82)], at: now)

        #expect(abs(ledger.todayTotal(at: now) - 0.58) < delta)
        #expect(ledger.todaySource(at: now) == .balanceDerived)
        #expect(abs(ledger.todayPoint(at: now).spend(for: .deepseek) - 0.58) < delta)
    }

    @Test func aTopUpIsMoneyAddedAndNeverSpend() {
        let seed = SurgeSnapshot(
            generatedAt: now.addingTimeInterval(-600),
            workspaces: [],
            balances: [balance("deepseek", 2.00)],
            dailySpend: []
        )
        var ledger = DailySpendLedger(seed: seed, calendar: calendar)

        ledger.record(workspaces: [], balances: [balance("deepseek", 22.00)], at: now)

        #expect(ledger.todayTotal(at: now) == 0)
        #expect(ledger.todayPoint(at: now).spendByProvider.isEmpty)
    }

    @Test func aBalanceDropReplacesTheDaysPerTurnFigures() {
        let seed = SurgeSnapshot(
            generatedAt: now.addingTimeInterval(-600),
            workspaces: [],
            balances: [balance("deepseek", 12.40)],
            dailySpend: []
        )
        var ledger = DailySpendLedger(seed: seed, calendar: calendar)
        let piTurn = agent(
            "session-pi",
            provider: "deepseek",
            cost: 0.03,
            source: .harnessReported,
            harness: HarnessIdentity(kind: .piAgent, sessionID: "session-pi", transport: .jsonl)
        )

        // The harness figure is inside the drop, so the drop is the day's figure, not the sum of both.
        ledger.record(workspaces: [workspace([piTurn])], balances: [balance("deepseek", 11.82)], at: now)

        #expect(abs(ledger.todayTotal(at: now) - 0.58) < delta)
        #expect(ledger.todaySource(at: now) == .balanceDerived)
    }

    @Test func aDayIsLabelledByItsWeakestSource() {
        var ledger = DailySpendLedger(calendar: calendar)
        let billed = agent(
            "worker-router",
            provider: "openrouter",
            cost: 0.10,
            source: .providerReported,
            account: "openrouter"
        )
        let estimated = agent(
            "session-claude",
            provider: "anthropic",
            cost: 0.05,
            source: .estimated,
            account: "anthropic"
        )

        ledger.record(workspaces: [workspace([billed, estimated])], at: now)

        #expect(abs(ledger.todayTotal(at: now) - 0.15) < delta)
        #expect(ledger.todaySource(at: now) == .estimated)
    }

    @Test func aSeededDayKeepsItsFamilyWhenTheSnapshotNamedTheHarness() {
        let seededPi = agent(
            "session-pi",
            provider: "pi",
            cost: 0.04,
            source: .estimated,
            harness: HarnessIdentity(kind: .piAgent, sessionID: "session-pi", transport: .jsonl)
        )
        let seed = SurgeSnapshot(
            generatedAt: now.addingTimeInterval(-600),
            workspaces: [workspace([seededPi])],
            balances: [balance("deepseek", 12.40)],
            dailySpend: [
                DailySpendPoint(date: day(-2), spendByProvider: ["pi": 0.04]),
                DailySpendPoint(date: day(-1), spendByProvider: ["anthropic": 0.20]),
            ]
        )

        let ledger = DailySpendLedger(seed: seed, calendar: calendar)
        let days = ledger.lastDays(3, at: now)

        // A snapshot written before the split keyed a pi session by its harness. It reads as the
        // family the account in that same snapshot names.
        #expect(days[0].spendByProvider == ["deepseek": 0.04])
        #expect(days[1].spendByProvider == ["anthropic": 0.20])
        #expect(days[0].spendByProvider["pi"] == nil)
    }

    @Test func aSeededDayReconcilesWithTheObservedDrop() {
        let seededPi = agent(
            "session-pi",
            provider: "deepseek",
            cost: 0.03,
            source: .estimated,
            harness: HarnessIdentity(kind: .piAgent, sessionID: "session-pi", transport: .jsonl)
        )
        let seed = SurgeSnapshot(
            generatedAt: now.addingTimeInterval(-600),
            workspaces: [workspace([seededPi])],
            balances: [balance("deepseek", 22.60)],
            dailySpend: [DailySpendPoint(date: now, spendByProvider: ["deepseek": 0.03])]
        )
        var ledger = DailySpendLedger(seed: seed, calendar: calendar)

        ledger.record(workspaces: [workspace([seededPi])], balances: [balance("deepseek", 22.52)], at: now)

        // The seeded figure was booked before the baseline, so the drop is measured from there and
        // the day reconciles to the money that actually left the account.
        #expect(abs(ledger.todayTotal(at: now) - 0.11) < delta)
        #expect(ledger.todaySource(at: now) == .balanceDerived)
    }

    @Test func anAgentWithNoAccountIsGroupedByItsKnownFamily() {
        var ledger = DailySpendLedger(calendar: calendar)
        let unknown = agent("worker-1", provider: "mystery-harness", cost: 0.02, source: .harnessReported, account: nil)

        ledger.record(workspaces: [workspace([unknown])], at: now)

        // "Other" is the family slot for a provider nobody named, and it is still not a harness name.
        #expect(ledger.todayPoint(at: now).spendByProvider == ["other": 0.02])
    }

    @Test func aLedgerKeepsOnlyTheRetentionWindow() {
        var ledger = DailySpendLedger(calendar: calendar)
        let old = agent("worker-old", provider: "deepseek", cost: 0.02, source: .harnessReported)
        let oldDay = day(-20)
        ledger.record(workspaces: [workspace([old])], at: oldDay)
        #expect(abs(ledger.todayTotal(at: oldDay) - 0.02) < delta)

        ledger.record(workspaces: [], at: now)

        #expect(ledger.todayTotal(at: oldDay) == 0)
        #expect(ledger.lastDays(DailySpendLedger.retentionDays, at: now).count == DailySpendLedger.retentionDays)
    }
}
