import Foundation
import SurgeCore
import Testing

@Suite("Billing resolution")
struct BillingTests {
    private static let referenceDate = SurgeFixtures.referenceDate

    private static func account(
        _ id: String,
        family: Provider,
        authority: CostSource,
        prefixes: [String]
    ) -> BillingAccount {
        BillingAccount(id: id, family: family, credentialRef: id, authority: authority, modelPrefixes: prefixes)
    }

    private static let twoDeepSeekAccounts = BillingConfiguration(
        accounts: [
            account("deepseek-personal", family: .deepseek, authority: .balanceDerived, prefixes: ["deepseek"]),
            account("deepseek-work", family: .deepseek, authority: .balanceDerived, prefixes: ["deepseek"]),
            BillingAccount.standard[2],
        ]
    )

    @Test func anExplicitBindingWinsOverTheSingleMatchItWouldOtherwiseUse() {
        let openRouter = BillingAccount.standard[2]
        let configuration = BillingConfiguration(
            accounts: BillingAccount.standard,
            bindings: [
                BillingBinding(harness: .claudeCode, modelPrefix: "claude", accountID: openRouter.id)
            ]
        )

        let attribution = BillingResolver.attribution(
            harness: .claudeCode,
            modelName: "claude-sonnet",
            configuration: configuration
        )

        #expect(attribution.account?.id == "openrouter")
        if case .account(_, let basis) = attribution {
            #expect(basis == .binding)
        } else {
            Issue.record("Expected the binding to resolve to an account")
        }
    }

    @Test func aBindingForAnotherHarnessDoesNotApply() {
        let configuration = BillingConfiguration(
            accounts: BillingAccount.standard,
            bindings: [
                BillingBinding(harness: .codex, modelPrefix: "claude", accountID: "openrouter")
            ]
        )

        let attribution = BillingResolver.attribution(
            harness: .claudeCode,
            modelName: "claude-sonnet",
            configuration: configuration
        )

        #expect(attribution.account?.id == "anthropic")
    }

    @Test func oneUnambiguousAccountMatchResolvesWithoutABinding() {
        let attribution = BillingResolver.attribution(
            harness: .claudeCode,
            modelName: "claude-sonnet-4-5",
            configuration: .standard
        )

        #expect(attribution.account?.id == "anthropic")
        if case .account(_, let basis) = attribution {
            #expect(basis == .modelPrefix)
        } else {
            Issue.record("Expected a single account match")
        }
    }

    @Test func twoMatchingAccountsStayAmbiguousAndAreNeverGuessed() {
        let attribution = BillingResolver.attribution(
            harness: .codex,
            modelName: "deepseek-chat",
            configuration: Self.twoDeepSeekAccounts
        )

        #expect(attribution.account == nil)
        #expect(attribution.isAmbiguous)
        guard case .ambiguous(let ids) = attribution else {
            Issue.record("Expected the match to stay ambiguous")
            return
        }
        #expect(ids == ["deepseek-personal", "deepseek-work"])
    }

    @Test func anAmbiguousMatchFallsBackToTheHarnessFigureAndIsLabelledThatWay() {
        let attribution = BillingResolver.attribution(
            harness: .codex,
            modelName: "deepseek-chat",
            configuration: Self.twoDeepSeekAccounts
        )
        let figures = TurnFigures(harnessReportedUSD: 0.42, estimateUSD: 0.31)

        let booked = BillingResolver.book(figures, attribution: attribution)

        #expect(booked?.source == .harnessReported)
        #expect(abs((booked?.amountUSD ?? 0) - 0.42) < 0.000_001)
    }

    @Test func anAmbiguousMatchWithNoHarnessFigureFallsBackToALocalEstimate() {
        let attribution = BillingResolver.attribution(
            harness: .codex,
            modelName: "deepseek-chat",
            configuration: Self.twoDeepSeekAccounts
        )

        let booked = BillingResolver.book(TurnFigures(estimateUSD: 0.31), attribution: attribution)

        #expect(booked?.source == .estimated)
        #expect(abs((booked?.amountUSD ?? 0) - 0.31) < 0.000_001)
    }

    @Test func noMatchAndNoFigureBooksNothingRatherThanZero() {
        let booked = BillingResolver.book(TurnFigures(), attribution: .none)
        #expect(booked == nil)
    }

    @Test func aRouterBindingBookstheProvidersBillOverTheHarnessListPrice() throws {
        let openRouter = BillingAccount.standard[2]
        let configuration = BillingConfiguration(
            accounts: BillingAccount.standard,
            bindings: [
                BillingBinding(harness: .claudeCode, modelPrefix: "claude", accountID: openRouter.id)
            ]
        )
        let attribution = BillingResolver.attribution(
            harness: .claudeCode,
            modelName: "claude-sonnet",
            configuration: configuration
        )
        // Claude Code's own totalCostUSD is computed at Anthropic list prices, so it is higher
        // than what OpenRouter actually billed.
        let figures = TurnFigures(providerReportedUSD: 0.0412, harnessReportedUSD: 0.0550, estimateUSD: 0.0500)

        let booked = try #require(BillingResolver.book(figures, attribution: attribution))

        #expect(booked.source == .providerReported)
        #expect(abs(booked.amountUSD - 0.0412) < 0.000_001)
    }

    @Test func aSubscriptionAccountBooksItsWindowRatherThanABill() throws {
        let subscription = BillingAccount(
            id: "anthropic",
            family: .anthropic,
            credentialRef: "anthropic",
            authority: .quotaWindow,
            modelPrefixes: ["claude"]
        )
        let configuration = BillingConfiguration(
            accounts: [subscription],
            quotaWindows: ["anthropic": QuotaWindow(preset: .claudeMax5x)]
        )
        let attribution = BillingResolver.attribution(
            harness: .claudeCode,
            modelName: "claude-sonnet",
            configuration: configuration
        )

        let booked = try #require(
            BillingResolver.book(
                TurnFigures(harnessReportedUSD: 0.55, estimateUSD: 0.50),
                attribution: attribution
            )
        )

        #expect(booked.source == .quotaWindow)
        #expect(abs(booked.amountUSD - 0.55) < 0.000_001)
    }

    @Test func aModelPrefixMatchIgnoresCaseAndSurroundingSpace() {
        let account = Self.account(
            "custom",
            family: .other,
            authority: .providerReported,
            prefixes: ["  DeepSeek  "]
        )

        #expect(account.matches(modelName: "deepseek-reasoner"))
        #expect(account.matches(modelName: "DEEPSEEK-chat"))
        #expect(account.matches(modelName: "openrouter/deepseek-chat") == false)
    }

    @Test func aVendorRoutedIDMatchesBothTheVendorAndTheRouter() {
        let attribution = BillingResolver.attribution(
            harness: .generic,
            modelName: "deepseek/deepseek-chat",
            configuration: .standard
        )
        #expect(attribution.isAmbiguous)
        guard case .ambiguous(let ids) = attribution else {
            Issue.record("Expected two accounts to match a vendor-routed id")
            return
        }
        #expect(ids == ["deepseek", "openrouter"])

        // The same model named without the vendor prefix belongs to one account only.
        #expect(
            BillingResolver.attribution(
                harness: .generic,
                modelName: "deepseek-chat",
                configuration: .standard
            ).account?.id == "deepseek"
        )
        #expect(
            BillingResolver.attribution(
                harness: .generic,
                modelName: "anthropic/claude-sonnet-4",
                configuration: .standard
            ).account?.id == "openrouter"
        )
    }

    @Test func thePresetCarriesThePlanWindowAndANotionalCeiling() {
        let pro = QuotaWindow(preset: .claudePro)
        let max5x = QuotaWindow(preset: .claudeMax5x)
        let max20x = QuotaWindow(preset: .claudeMax20x)
        let custom = QuotaWindow(preset: .custom)

        #expect(pro.interval == 5 * 3600)
        #expect(pro.limitUSD == 20)
        #expect(max5x.limitUSD == 100)
        #expect(max20x.limitUSD == 200)
        #expect(custom.preset.name == "Custom window")
        // The interval is never zero, so a window can never divide by zero.
        let tiny = QuotaWindow(preset: .custom, interval: 0, limitUSD: 0)
        #expect(tiny.interval >= 60)
    }

    @Test func aFixedWindowResetsOnItsGridAndClearsTheBurn() {
        var window = QuotaWindow(preset: .claudePro, style: .reset, interval: 5 * 3600, limitUSD: 20)
        var state = QuotaWindowState(window: window, startedAt: Self.referenceDate)
        state.book(4.00)

        #expect(abs(state.usedUSD - 4.00) < 0.000_001)
        #expect(abs(state.headroomUSD - 16.00) < 0.000_001)
        #expect(state.percentUsed == 20)
        #expect(state.isExpired(at: Self.referenceDate.addingTimeInterval(3600)) == false)

        state.advance(to: Self.referenceDate.addingTimeInterval(5 * 3600 + 60))

        #expect(state.usedUSD == 0)
        #expect(abs(state.headroomUSD - 20) < 0.000_001)
        #expect(state.startedAt == Self.referenceDate.addingTimeInterval(5 * 3600))
        #expect(state.resetsAt == Self.referenceDate.addingTimeInterval(10 * 3600))
    }

    @Test func aRollingWindowReanchorsWhenItExpiresAndKeepsItsBurnInsideTheWindow() {
        var window = QuotaWindow(preset: .custom, style: .rolling, interval: 3600, limitUSD: 10)
        var state = QuotaWindowState(window: window, startedAt: Self.referenceDate)
        state.book(3.50)
        let bookTime = Self.referenceDate.addingTimeInterval(1800)

        state.advance(to: bookTime)
        #expect(abs(state.usedUSD - 3.50) < 0.000_001)
        #expect(abs(state.headroomUSD - 6.50) < 0.000_001)
        #expect(state.percentUsed == 35)

        let afterReset = Self.referenceDate.addingTimeInterval(3601)
        state.advance(to: afterReset)

        #expect(state.usedUSD == 0)
        #expect(state.startedAt == afterReset)
        #expect(state.resetsAt == afterReset.addingTimeInterval(3600))
        #expect(state.isOverWindow == false)
    }

    @Test func burnPastTheCeilingReadsAsFullHeadroomRatherThanNegative() {
        let window = QuotaWindow(preset: .custom, interval: 3600, limitUSD: 10)
        var state = QuotaWindowState(window: window, startedAt: Self.referenceDate)
        state.book(14.00)

        #expect(state.headroomUSD == 0)
        #expect(state.percentUsed == 100)
        #expect(state.isOverWindow)
    }
}
