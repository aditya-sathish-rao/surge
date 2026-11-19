import Foundation
import SurgeCore
import Testing

@testable import SurgeWallets

private let pollDate = SurgeFixtures.referenceDate

/// Every poll that ends without an amount has to say why, and the reason may only ever be a
/// category plus a status code.
@Suite("Wallet unavailable reasons")
struct WalletUnavailableReasonTests {
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

        #expect(updates.map(\.reason) == [BalanceUnavailableReason(.notConfigured)])
        #expect(updates.first?.account?.amountUSD == nil)
        #expect(await transport.sentRequests.isEmpty)
        #expect(await scheduler.requestedDelays == [10])
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

        #expect(updates.map(\.reason) == [BalanceUnavailableReason(.keyUnavailable)])
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
        let keyRejected = BalanceUnavailableReason(.keyRejected, statusCode: 401)
        #expect(deepSeekUpdates.allSatisfy { $0.reason == keyRejected })
        #expect(deepSeekUpdates.allSatisfy { $0.account?.amountUSD == nil })
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

        #expect(updates.map(\.reason) == [BalanceUnavailableReason(.unreachable)])
        #expect(updates.first?.account?.lastPolledAt == pollDate)
    }

    @Test("A 403 is a rejected key too")
    func forbiddenIsKeyRejected() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 403, body: WalletFixtures.unauthorized)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates.map(\.reason) == [BalanceUnavailableReason(.keyRejected, statusCode: 403)])
    }

    @Test("A status Surge cannot use is an unexpected response that keeps its code")
    func serverErrorIsUnexpectedResponse() async {
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 503, body: WalletFixtures.unauthorized)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            transport: transport,
            scheduler: scheduler
        )

        #expect(updates.map(\.reason) == [BalanceUnavailableReason(.unexpectedResponse, statusCode: 503)])
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

        #expect(updates.map(\.reason) == [BalanceUnavailableReason(.unexpectedResponse, statusCode: 200)])
        #expect(updates.first?.account?.amountUSD == nil)
    }

    @Test("A reason can never carry the key or the provider's body")
    func reasonCarriesNoPayload() async throws {
        let leakyBody = """
            {
              "error": {
                "message": "Incorrect API key provided: sk-live-secret-key",
                "detail": "quota marker from the response body"
              }
            }
            """
        let scheduler = ScriptedScheduler(date: pollDate, stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 401, body: leakyBody)])

        let updates = await collectUpdates(
            configuration: configuration(for: TestAccounts.deepSeek, pollInterval: 10),
            keys: StubKeys(deepSeek: "sk-live-secret-key"),
            transport: transport,
            scheduler: scheduler
        )

        let balance = try #require(updates.first?.account)
        let reason = try #require(balance.unavailableReason)
        #expect(reason.category == .keyRejected)

        let encoder = JSONEncoder()
        let encodedBalance = try #require(String(data: encoder.encode(balance), encoding: .utf8))
        let encodedReason = try #require(String(data: encoder.encode(reason), encoding: .utf8))
        for encoded in [encodedBalance, encodedReason] {
            #expect(!encoded.contains("sk-live-secret-key"))
            #expect(!encoded.contains("Incorrect API key"))
            #expect(!encoded.contains("quota marker"))
        }

        // A reason is a category and a status code: there is no field for free text to hide in.
        let fields = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(reason)) as? [String: Any]
        )
        #expect(Set(fields.keys) == ["category", "statusCode"])
    }
}
