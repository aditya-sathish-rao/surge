import Foundation
import SurgeCore
import Testing

@testable import SurgeUI

struct BalancesTests {
    @Test func availableBalanceShowsTheAmount() {
        let presentation = BalancePresentation(
            balance: AccountBalance(provider: "deepseek", amountUSD: 12.40, lastPolledAt: UITestFixtures.now)
        )

        #expect(presentation.provider == .deepseek)
        #expect(presentation.providerName == "DeepSeek")
        #expect(presentation.amountText == "$12.40")
        #expect(presentation.qualifier == nil)
        #expect(presentation.level == .normal)
        #expect(presentation.isUnavailable == false)
        #expect(presentation.accessibilityLabel == "DeepSeek, balance $12.40")
    }

    @Test func lowBalanceAddsTheLowWord() {
        let presentation = BalancePresentation(
            balance: AccountBalance(provider: "openrouter", amountUSD: 3.20, lastPolledAt: UITestFixtures.now)
        )

        #expect(presentation.amountText == "$3.20")
        #expect(presentation.qualifier == "Low")
        #expect(presentation.level == .low)
        #expect(presentation.accessibilityLabel == "OpenRouter, balance $3.20, low")
    }

    @Test func emptyBalanceAddsTheEmptyWord() {
        let presentation = BalancePresentation(
            balance: AccountBalance(provider: "openrouter", amountUSD: 0.20, lastPolledAt: UITestFixtures.now)
        )

        #expect(presentation.qualifier == "Empty")
        #expect(presentation.level == .empty)
        #expect(presentation.accessibilityLabel == "OpenRouter, balance $0.20, empty")
    }

    @Test func missingEndpointSaysBalanceUnavailable() {
        let presentation = BalancePresentation(
            balance: AccountBalance(provider: "anthropic", amountUSD: nil, lastPolledAt: UITestFixtures.now)
        )

        #expect(presentation.amountText == "Balance unavailable")
        #expect(presentation.reasonText == nil)
        #expect(presentation.qualifier == nil)
        #expect(presentation.level == nil)
        #expect(presentation.isUnavailable)
        #expect(presentation.accessibilityLabel == "Anthropic, balance unavailable")
    }

    @Test func aRejectedKeySaysWhyTheBalanceIsMissing() {
        let presentation = BalancePresentation(
            balance: AccountBalance(
                provider: "deepseek",
                amountUSD: nil,
                lastPolledAt: UITestFixtures.now,
                unavailableReason: BalanceUnavailableReason(.keyRejected, statusCode: 401)
            )
        )

        #expect(presentation.amountText == "Balance unavailable")
        #expect(presentation.reasonText == "Key rejected")
        #expect(presentation.level == nil)
        #expect(presentation.isUnavailable)
        #expect(presentation.accessibilityLabel == "DeepSeek, balance unavailable. Key rejected.")
    }

    @Test func anAnsweredButUnreachableProviderSaysSoInstead() {
        let presentation = BalancePresentation(
            balance: AccountBalance(
                provider: "openrouter",
                amountUSD: nil,
                lastPolledAt: UITestFixtures.now,
                unavailableReason: BalanceUnavailableReason(.unreachable)
            )
        )

        #expect(presentation.amountText == "Balance unavailable")
        #expect(presentation.reasonText == "Could not reach provider")
        #expect(presentation.accessibilityLabel == "OpenRouter, balance unavailable. Could not reach provider.")
    }

    @Test func anAmountNeverCarriesAReason() {
        let presentation = BalancePresentation(
            balance: AccountBalance(provider: "deepseek", amountUSD: 12.40, lastPolledAt: UITestFixtures.now)
        )

        #expect(presentation.reasonText == nil)
    }

    @Test func aFailedKeyCapPollExplainsItselfRatherThanClaimingNoLimit() {
        let presentation = BalancePresentation(
            balance: AccountBalance(
                provider: "openrouter",
                amountUSD: nil,
                lastPolledAt: UITestFixtures.now,
                kind: .keyLimit,
                unavailableReason: BalanceUnavailableReason(.unexpectedResponse, statusCode: 200)
            )
        )

        #expect(presentation.amountText == "Balance unavailable")
        #expect(presentation.reasonText == "Unexpected response")
    }

    @Test func fixtureBalancesCoverAllThreeCases() {
        let presentations = SurgeFixtures.balances.map(BalancePresentation.init)

        #expect(presentations.map(\.amountText) == ["Balance unavailable", "$12.40", "$3.20"])
        #expect(presentations.map(\.qualifier) == [nil, nil, "Low"])
    }

    @Test func aKeyCapNeverPretendsToBeAWalletBalance() {
        let presentation = BalancePresentation(
            balance: AccountBalance(
                provider: "openrouter",
                amountUSD: 3.20,
                lastPolledAt: UITestFixtures.now,
                kind: .keyLimit
            )
        )

        #expect(presentation.amountText == "$3.20 key cap")
        #expect(presentation.qualifier == "Low")
        #expect(presentation.accessibilityLabel == "OpenRouter, key cap $3.20, low")
    }

    @Test func aKeyWithoutALimitShowsUsageButNoAmount() {
        let presentation = BalancePresentation(
            balance: AccountBalance(
                provider: "openrouter",
                amountUSD: nil,
                lastPolledAt: UITestFixtures.now,
                kind: .keyLimit,
                usageUSD: 4.25
            )
        )

        #expect(presentation.amountText == "No key limit")
        #expect(presentation.reasonText == nil)
        #expect(presentation.usageText == "used $4.25")
        #expect(presentation.isUnavailable)
        #expect(presentation.accessibilityLabel == "OpenRouter, no key limit set, used $4.25")
    }

    @Test func freshnessCaptionReadsLikeTheDesign() {
        let now = UITestFixtures.now

        #expect(
            BalanceFreshness.caption(lastPolledAt: now.addingTimeInterval(-12), now: now)
                == "// updated 12s ago"
        )
        #expect(
            BalanceFreshness.caption(lastPolledAt: now.addingTimeInterval(-95), now: now)
                == "// updated 1m 35s ago"
        )
        #expect(
            BalanceFreshness.caption(lastPolledAt: now.addingTimeInterval(-3_900), now: now)
                == "// updated 1h 5m ago"
        )
        #expect(BalanceFreshness.caption(lastPolledAt: nil, now: now) == "// not polled yet")
    }

    @Test func theNewestPollDrivesTheCaption() {
        let now = UITestFixtures.now
        let balances = [
            AccountBalance(provider: "deepseek", amountUSD: 12.40, lastPolledAt: now.addingTimeInterval(-90)),
            AccountBalance(provider: "openrouter", amountUSD: 3.20, lastPolledAt: now.addingTimeInterval(-10)),
        ]

        #expect(BalanceFreshness.lastPolledAt(in: balances) == now.addingTimeInterval(-10))
        #expect(BalanceFreshness.lastPolledAt(in: []) == nil)
    }

    @Test func aFuturePollNeverShowsNegativeTime() {
        #expect(
            BalanceFreshness.caption(lastPolledAt: UITestFixtures.now.addingTimeInterval(30), now: UITestFixtures.now)
                == "// updated 0s ago"
        )
    }
}
