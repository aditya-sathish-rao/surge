import Foundation
import SurgeCore
import Testing

@testable import SurgeWallets

private let pollDate = SurgeFixtures.referenceDate

@Suite("Wallet polling")
struct WalletPollerTests {
    @Test("DeepSeek balance parses the documented response into a loaded update")
    func deepSeekBalanceIsLoaded() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.deepSeekBalance)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates.count == 1)
        guard case .loaded(let balance) = updates.first else {
            Issue.record("expected a loaded balance, got \(String(describing: updates.first))")
            return
        }
        #expect(balance.provider == Provider.deepseek.rawValue)
        #expect(balance.amountUSD == 12.40)
        #expect(balance.lastPolledAt == pollDate)
    }

    @Test("OpenRouter balance is the key's limit minus its usage")
    func openRouterBalanceIsLimitMinusUsage() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.openRouterKey)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.openRouter, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        guard case .loaded(let balance) = updates.first else {
            Issue.record("expected a loaded balance, got \(String(describing: updates.first))")
            return
        }
        #expect(balance.provider == Provider.openrouter.rawValue)
        #expect(balance.amountUSD == 8.50)
    }

    @Test("An OpenRouter key without a limit reports unavailable but keeps its usage")
    func openRouterWithoutLimitIsUnavailable() async throws {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.openRouterKeyWithoutLimit)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.openRouter, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates == [.unavailable(provider: Provider.openrouter.rawValue, lastPolledAt: pollDate)])

        let balance = try OpenRouterBalanceParser().balance(from: Data(WalletFixtures.openRouterKeyWithoutLimit.utf8))
        #expect(balance.amountUSD == nil)
        #expect(balance.cumulativeUsageUSD == 4.25)
    }

    @Test("A provider with no balance endpoint is unavailable without a network call")
    func unconfiguredProviderIsUnavailable() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 2)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.deepSeekBalance)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.anthropic, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates == Array(repeating: .unavailable(provider: "anthropic", lastPolledAt: pollDate), count: 2))
        #expect(await transport.sentRequests.isEmpty)
        #expect(await scheduler.requestedDelays == [10, 10])
    }

    @Test("An account without a stored key is unavailable without a network call")
    func missingKeyIsUnavailable() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.deepSeekBalance)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            keys: StubKeys(deepSeek: nil),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates == [.unavailable(provider: Provider.deepseek.rawValue, lastPolledAt: pollDate)])
        #expect(await transport.sentRequests.isEmpty)
    }

    @Test("A Keychain failure is unavailable without a network call")
    func keychainFailureIsUnavailable() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.deepSeekBalance)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            keys: FailingKeys(),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates == [.unavailable(provider: Provider.deepseek.rawValue, lastPolledAt: pollDate)])
        #expect(await transport.sentRequests.isEmpty)
    }

    @Test("A 401 degrades only the account that failed")
    func unauthorizedDegradesOneAccount() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 4)
        let transport = StubTransport(
            byURL: [
                TestEndpoints.deepSeekString: [
                    .response(statusCode: 401, body: WalletFixtures.unauthorized)
                ],
                TestEndpoints.openRouterString: [
                    .response(statusCode: 200, body: WalletFixtures.openRouterKey)
                ],
            ]
        )

        let updates = await collectUpdates(
            configuration: WalletConfiguration(
                accounts: [TestAccounts.deepSeek, TestAccounts.openRouter],
                pollInterval: 10
            ),
            transport: transport,
            scheduler: scheduler
        )

        let deepSeekUpdates = updates.filter { $0.provider == Provider.deepseek.rawValue }
        let openRouterUpdates = updates.filter { $0.provider == Provider.openrouter.rawValue }
        #expect(!deepSeekUpdates.isEmpty)
        let unavailable = BalanceUpdate.unavailable(provider: "deepseek", lastPolledAt: pollDate)
        #expect(deepSeekUpdates.allSatisfy { $0 == unavailable })
        #expect(openRouterUpdates.contains { $0.isLoaded(amount: 8.50) })
        #expect(await transport.sentRequests.count >= 2)
    }

    @Test("A timeout degrades that account to unavailable")
    func timeoutIsUnavailable() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.timeout])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.openRouter, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates == [.unavailable(provider: Provider.openrouter.rawValue, lastPolledAt: pollDate)])
    }

    @Test("Malformed JSON degrades that account to unavailable")
    func malformedJSONIsUnavailable() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.malformed)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates == [.unavailable(provider: Provider.deepseek.rawValue, lastPolledAt: pollDate)])
    }

    @Test("Backoff doubles on each failure and stops at the cap")
    func backoffGrowsAndCaps() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 5)
        let transport = StubTransport([.response(statusCode: 500, body: WalletFixtures.unauthorized)])

        _ = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(await scheduler.requestedDelays == [10, 20, 40, 80, 80])
    }

    @Test("Backoff resets after a successful poll")
    func backoffResetsAfterSuccess() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 5)
        let transport = StubTransport([
            .response(statusCode: 500, body: WalletFixtures.unauthorized),
            .response(statusCode: 500, body: WalletFixtures.unauthorized),
            .response(statusCode: 200, body: WalletFixtures.deepSeekBalance),
            .response(statusCode: 500, body: WalletFixtures.unauthorized),
            .response(statusCode: 200, body: WalletFixtures.deepSeekBalance),
        ])

        _ = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(await scheduler.requestedDelays == [10, 20, 10, 10, 10])
    }

    @Test("The poll interval is injected and used for every successful tick")
    func pollIntervalIsInjected() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 3)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.deepSeekBalance)])

        _ = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 7),
            transport: transport,
            scheduler: scheduler
        )

        #expect(await scheduler.requestedDelays == [7, 7, 7])
    }

    @Test("The key travels in the Authorization header, never in the URL")
    func keyIsSentAsBearerHeader() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.deepSeekBalance)])

        _ = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            keys: StubKeys(deepSeek: "sk-secret"),
            transport: transport,
            scheduler: scheduler
        )

        let sent = await transport.sentRequests
        #expect(sent.count == 1)
        #expect(sent.first?.authorization == "Bearer sk-secret")
        #expect(sent.first?.url == TestEndpoints.deepSeekString)
        #expect(sent.first?.method == "GET")
        #expect(sent.first?.timeout == WalletConfiguration.defaultRequestTimeout)
    }
}

@Suite("Wallet response parsing")
struct WalletParsingTests {
    @Test("An unavailable DeepSeek response has no amount to report")
    func deepSeekUnavailableBodyThrows() {
        #expect(throws: WalletResponseError.malformedBody) {
            try DeepSeekBalanceParser().balance(from: Data(WalletFixtures.deepSeekNoBalance.utf8))
        }
    }

    @Test("Malformed DeepSeek JSON throws instead of guessing")
    func deepSeekMalformedBodyThrows() {
        #expect(throws: WalletResponseError.malformedBody) {
            try DeepSeekBalanceParser().balance(from: Data(WalletFixtures.malformed.utf8))
        }
    }

    @Test("OpenRouter usage beyond the limit reports an empty balance, not a negative one")
    func openRouterOverLimitClampsAtZero() throws {
        let body = """
            { "data": { "usage": 1.5, "limit": 1.0 } }
            """
        let balance = try OpenRouterBalanceParser().balance(from: Data(body.utf8))
        #expect(balance.amountUSD == 0)
        #expect(balance.cumulativeUsageUSD == 1.5)
    }

    @Test("Malformed OpenRouter JSON throws instead of guessing")
    func openRouterMalformedBodyThrows() {
        #expect(throws: WalletResponseError.malformedBody) {
            try OpenRouterBalanceParser().balance(from: Data(WalletFixtures.malformed.utf8))
        }
    }
}

@Suite("Wallet backoff")
struct WalletBackoffTests {
    @Test("A policy never waits longer than its cap")
    func delayCaps() {
        let policy = BackoffPolicy(initialDelay: 60, maximumDelay: 300)
        #expect(policy.delay(afterFailures: 0) == 60)
        #expect(policy.delay(afterFailures: 1) == 60)
        #expect(policy.delay(afterFailures: 2) == 120)
        #expect(policy.delay(afterFailures: 3) == 240)
        #expect(policy.delay(afterFailures: 4) == 300)
        #expect(policy.delay(afterFailures: 1_000) == 300)
    }
}

private func configuration(for account: WalletAccount, pollInterval: TimeInterval) -> WalletConfiguration {
    WalletConfiguration(accounts: [account], pollInterval: pollInterval)
}

extension BalanceUpdate {
    fileprivate var provider: String {
        switch self {
        case .loaded(let balance): balance.provider
        case .unavailable(let provider, _): provider
        }
    }

    fileprivate func isLoaded(amount: Double) -> Bool {
        if case .loaded(let balance) = self { return balance.amountUSD == amount }
        return false
    }
}
