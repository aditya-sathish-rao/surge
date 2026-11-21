import Foundation
import SurgeCore
import Testing

struct FormattingTests {
    private let now = SurgeFixtures.referenceDate

    @Test func costUsesUSDDollars() {
        #expect(SurgeFormatting.cost(1.42) == "$1.42")
        #expect(SurgeFormatting.cost(12.4) == "$12.40")
    }

    @Test func contextPercentRoundsAndClamps() {
        #expect(SurgeFormatting.percent(0.705) == "71%")
        #expect(SurgeFormatting.percent(-0.2) == "0%")
        #expect(SurgeFormatting.percent(1.4) == "100%")
    }

    @Test func tokenRateRoundsToWholeTokens() {
        #expect(SurgeFormatting.tokenRate(411.6) == "412 tok/s")
        #expect(SurgeFormatting.tokenRate(-3) == "0 tok/s")
    }

    @Test func durationsReadTheWayTheDesignFileSpecifies() {
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-42), now: now) == "42s")
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-240), now: now) == "4m")
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-194), now: now) == "3m 14s")
        #expect(SurgeFormatting.duration(since: now.addingTimeInterval(-7_200), now: now) == "2h 0m")
        #expect(SurgeFormatting.minutesDuration(since: now.addingTimeInterval(-2_520), now: now) == "42m")
    }

    @Test func statusWordsCarryNoElapsedTime() {
        #expect(SurgeFormatting.statusWord(.working) == "Working")
        #expect(SurgeFormatting.statusWord(.waitingForYou) == "Waiting for you")
        #expect(SurgeFormatting.statusWord(.compacting) == "Compacting")
        #expect(SurgeFormatting.statusWord(.noSignal) == "No signal")
        #expect(SurgeFormatting.statusWord(.stalled(since: now.addingTimeInterval(-194))) == "Stalled")
        #expect(SurgeFormatting.statusWord(.idle(since: now.addingTimeInterval(-240))) == "Idle")
        #expect(SurgeFormatting.statusWord(.done) == "Done")
    }

    @Test func statusLabelsCarryWordsAndElapsedTime() {
        #expect(SurgeFormatting.statusLabel(.working, now: now) == "Working")
        #expect(SurgeFormatting.statusLabel(.waitingForYou, now: now) == "Waiting for you")
        #expect(SurgeFormatting.statusLabel(.compacting, now: now) == "Compacting")
        #expect(SurgeFormatting.statusLabel(.noSignal, now: now) == "No signal")
        #expect(
            SurgeFormatting.statusLabel(.stalled(since: now.addingTimeInterval(-194)), now: now) == "Stalled 3m 14s"
        )
        #expect(SurgeFormatting.statusLabel(.idle(since: now.addingTimeInterval(-240)), now: now) == "Idle 4m")
        #expect(
            SurgeFormatting.statusLabel(.done, now: now, lastActivityAt: now.addingTimeInterval(-2_520)) == "Done · 42m"
        )
        #expect(SurgeFormatting.statusLabel(.done, now: now) == "Done")
    }

    @Test func balanceLabelDistinguishesLowEmptyAndUnavailable() {
        let low = AccountBalance(provider: "openrouter", amountUSD: 3.20, lastPolledAt: now)
        let empty = AccountBalance(provider: "openrouter", amountUSD: 0.20, lastPolledAt: now)
        let healthy = AccountBalance(provider: "deepseek", amountUSD: 12.40, lastPolledAt: now)
        let unavailable = AccountBalance(provider: "anthropic", amountUSD: nil, lastPolledAt: now)

        #expect(SurgeFormatting.balanceLabel(low) == "$3.20 · Low")
        #expect(SurgeFormatting.balanceLabel(empty) == "$0.20 · Empty")
        #expect(SurgeFormatting.balanceLabel(healthy) == "$12.40")
        #expect(SurgeFormatting.balanceLabel(unavailable) == "Balance unavailable")
    }

    @Test func menuBarReadoutKeepsTheLabelWithTheNumber() {
        #expect(
            SurgeFormatting.menuBarReadout(
                orchestrators: 1,
                workers: 2,
                spend: SpendFigure(amountUSD: 1.42, source: .estimated)
            ) == "1 Orch, 2 Workers, $1.42 est.")
        #expect(
            SurgeFormatting.menuBarReadout(
                orchestrators: 2,
                workers: 1,
                spend: SpendFigure(amountUSD: 0, source: .estimated)
            ) == "2 Orchs, 1 Worker, $0.00 est.")
    }
}
