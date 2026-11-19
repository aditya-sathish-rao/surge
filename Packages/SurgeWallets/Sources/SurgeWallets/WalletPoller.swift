import Foundation
import SurgeCore

/// Polls every configured account on the wallet cadence and publishes one update per poll.
///
/// Accounts are polled concurrently, so a provider that fails or times out degrades only
/// its own row to unavailable and never delays the others.
public struct WalletPoller: WalletPolling {
    private let configuration: WalletConfiguration
    private let keys: any WalletKeyProviding
    private let transport: any WalletTransport
    private let scheduler: any WalletScheduler

    public init(
        configuration: WalletConfiguration = WalletConfiguration(),
        keys: any WalletKeyProviding,
        transport: any WalletTransport = URLSessionWalletTransport(),
        scheduler: any WalletScheduler = SystemWalletScheduler()
    ) {
        self.configuration = configuration
        self.keys = keys
        self.transport = transport
        self.scheduler = scheduler
    }

    public func updates() -> AsyncStream<BalanceUpdate> {
        AsyncStream { continuation in
            let polling = Task {
                await withTaskGroup(of: Void.self) { group in
                    for account in configuration.accounts {
                        group.addTask {
                            await poll(account, publish: { continuation.yield($0) })
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in polling.cancel() }
        }
    }

    private func poll(_ account: WalletAccount, publish: @escaping @Sendable (BalanceUpdate) -> Void) async {
        var failures = 0
        while !Task.isCancelled {
            let outcome = await read(account)
            publish(outcome.update)
            failures = outcome.succeeded ? 0 : failures + 1
            let delay =
                outcome.succeeded
                ? configuration.pollInterval
                : configuration.backoff.delay(afterFailures: failures)
            do {
                try await scheduler.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    private struct Outcome {
        let update: BalanceUpdate
        let succeeded: Bool
    }

    private func read(_ account: WalletAccount) async -> Outcome {
        let polledAt = await scheduler.now()
        let provider = account.provider.rawValue
        let unavailable = Outcome(
            update: .unavailable(provider: provider, lastPolledAt: polledAt),
            succeeded: true
        )

        // No endpoint or no key means there is nothing to retry: hold the normal cadence.
        guard let url = account.balanceURL, let parser = Self.parser(for: account.provider) else {
            return unavailable
        }
        guard let key = try? keys.apiKey(for: account.provider) else {
            return unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let response = try await transport.get(request)
            guard response.isSuccess else { return failed(provider: provider, polledAt: polledAt) }
            let balance = try parser.balance(from: response.body)
            return Outcome(
                update: Self.update(provider: provider, balance: balance, polledAt: polledAt),
                succeeded: true
            )
        } catch {
            return failed(provider: provider, polledAt: polledAt)
        }
    }

    private func failed(provider: String, polledAt: Date) -> Outcome {
        Outcome(
            update: .unavailable(provider: provider, lastPolledAt: polledAt),
            succeeded: false
        )
    }

    private static func update(provider: String, balance: WalletBalance, polledAt: Date) -> BalanceUpdate {
        BalanceUpdate.loaded(
            AccountBalance(
                provider: provider,
                amountUSD: balance.amountUSD,
                lastPolledAt: polledAt,
                kind: balance.kind,
                usageUSD: balance.usageUSD
            )
        )
    }

    private static func parser(for provider: Provider) -> (any BalanceResponseParsing)? {
        switch provider {
        case .deepseek: DeepSeekBalanceParser()
        case .openrouter: OpenRouterBalanceParser()
        case .anthropic, .other: nil
        }
    }
}
