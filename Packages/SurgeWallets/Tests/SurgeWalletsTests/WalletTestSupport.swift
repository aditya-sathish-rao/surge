import Foundation
import SurgeCore

@testable import SurgeWallets

/// Replays scripted HTTP outcomes and records what the poller sent.
actor StubTransport: WalletTransport {
    enum Outcome: Sendable, Equatable {
        case response(statusCode: Int, body: String)
        case timeout
    }

    struct SentRequest: Sendable, Equatable {
        let url: String
        let method: String
        let authorization: String?
        let timeout: TimeInterval
    }

    private let scripts: [String: [Outcome]]
    private var indices: [String: Int] = [:]
    private(set) var sentRequests: [SentRequest] = []

    /// Replays one sequence of outcomes for every request.
    init(_ outcomes: [Outcome]) {
        self.init(byURL: ["": outcomes])
    }

    /// Replays a separate sequence per request URL, so accounts can fail independently.
    init(byURL scripts: [String: [Outcome]]) {
        precondition(scripts.values.allSatisfy { !$0.isEmpty }, "a stub transport needs at least one outcome")
        self.scripts = scripts
    }

    func get(_ request: URLRequest) async throws -> WalletHTTPResponse {
        sentRequests.append(
            SentRequest(
                url: request.url?.absoluteString ?? "",
                method: request.httpMethod ?? "",
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                timeout: request.timeoutInterval
            )
        )
        let key = request.url?.absoluteString ?? ""
        guard let script = scripts[key] ?? scripts[""], !script.isEmpty else {
            preconditionFailure("no scripted outcome for \(key)")
        }
        let index = min(indices[key, default: 0], script.count - 1)
        indices[key] = index + 1
        switch script[index] {
        case .response(let statusCode, let body):
            return WalletHTTPResponse(statusCode: statusCode, body: Data(body.utf8))
        case .timeout:
            throw URLError(.timedOut)
        }
    }
}

/// Returns instantly and records the delays it was asked to wait, so nothing waits.
actor ScriptedScheduler: WalletScheduler {
    private let date: Date
    private let stopAfterSleeps: Int
    private(set) var requestedDelays: [TimeInterval] = []

    init(date: Date, stopAfterSleeps: Int) {
        self.date = date
        self.stopAfterSleeps = stopAfterSleeps
    }

    func now() async -> Date {
        date
    }

    func sleep(for duration: TimeInterval) async throws {
        requestedDelays.append(duration)
        if requestedDelays.count >= stopAfterSleeps {
            throw CancellationError()
        }
    }
}

struct StubKeys: WalletKeyProviding {
    let keys: [String: String]

    init(deepSeek: String? = "deepseek-key", openRouter: String? = "openrouter-key") {
        var keys: [String: String] = [:]
        keys[Provider.deepseek.rawValue] = deepSeek
        keys[Provider.openrouter.rawValue] = openRouter
        self.keys = keys
    }

    func apiKey(for provider: Provider) throws -> String? {
        keys[provider.rawValue]
    }
}

struct FailingKeys: WalletKeyProviding {
    func apiKey(for provider: Provider) throws -> String? {
        throw WalletKeyError.keychainUnavailable(status: -25_308)
    }
}

enum TestEndpoints {
    static let deepSeekString = "https://api.deepseek.com/user/balance"
    static let openRouterString = "https://openrouter.ai/api/v1/auth/key"
    static let deepSeek = URL(string: deepSeekString)
    static let openRouter = URL(string: openRouterString)
}

enum TestAccounts {
    static let deepSeek = WalletAccount(provider: .deepseek, balanceURL: TestEndpoints.deepSeek)
    static let openRouter = WalletAccount(provider: .openrouter, balanceURL: TestEndpoints.openRouter)
    static let anthropic = WalletAccount(provider: .anthropic, balanceURL: nil)
}

/// Drains the poller's stream, which ends when the scripted scheduler stops.
func collectUpdates(
    configuration: WalletConfiguration,
    keys: any WalletKeyProviding = StubKeys(),
    transport: StubTransport,
    scheduler: ScriptedScheduler
) async -> [BalanceUpdate] {
    let poller = WalletPoller(
        configuration: configuration,
        keys: keys,
        transport: transport,
        scheduler: scheduler
    )
    var updates: [BalanceUpdate] = []
    for await update in poller.updates() {
        updates.append(update)
    }
    return updates
}

/// One account, polled on an injected cadence.
func configuration(for account: WalletAccount, pollInterval: TimeInterval) -> WalletConfiguration {
    WalletConfiguration(accounts: [account], pollInterval: pollInterval)
}

extension BalanceUpdate {
    /// The record a poll published, whichever case carried it.
    var account: AccountBalance? {
        if case .loaded(let balance) = self { return balance }
        return nil
    }

    /// Why the poll ended without an amount, read off the published record.
    var reason: BalanceUnavailableReason? {
        account?.unavailableReason
    }

    var provider: String {
        switch self {
        case .loaded(let balance): balance.provider
        case .unavailable(let provider, _): provider
        }
    }

    func isLoaded(amount: Double) -> Bool {
        if case .loaded(let balance) = self { return balance.amountUSD == amount }
        return false
    }
}
