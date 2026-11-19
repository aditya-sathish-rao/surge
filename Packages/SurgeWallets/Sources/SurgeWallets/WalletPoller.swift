import Foundation
import SurgeCore

/// Polls every configured account on the wallet cadence and publishes one update per poll.
///
/// Accounts are polled concurrently, so a provider that fails or times out degrades only
/// its own row and never delays the others. Every poll publishes a full account record, which
/// carries either the amount that was fetched or the reason there is none, so a caller never has
/// to guess why a row is empty.
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

        // No endpoint means there is nothing to ask for. That is a design fact, not a failure.
        guard let url = account.balanceURL, let parser = Self.parser(for: account.provider) else {
            return Outcome(
                update: .unavailable(provider: provider, lastPolledAt: polledAt),
                succeeded: true
            )
        }

        let key: String
        do {
            guard let stored = try keys.apiKey(for: account.provider) else {
                return report(.init(.notConfigured), provider: provider, polledAt: polledAt, succeeded: true)
            }
            key = stored
        } catch {
            return report(.init(.keyUnavailable), provider: provider, polledAt: polledAt, succeeded: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: WalletHTTPResponse
        do {
            response = try await transport.get(request)
        } catch {
            return report(.init(.unreachable), provider: provider, polledAt: polledAt, succeeded: false)
        }

        guard response.isSuccess else {
            let reason = BalanceUnavailableReason(
                Self.category(forStatus: response.statusCode),
                statusCode: response.statusCode
            )
            return report(reason, provider: provider, polledAt: polledAt, succeeded: false)
        }

        let balance: WalletBalance
        do {
            balance = try parser.balance(from: response.body)
        } catch {
            let reason = BalanceUnavailableReason(.unexpectedResponse, statusCode: response.statusCode)
            return report(reason, provider: provider, polledAt: polledAt, succeeded: false)
        }
        return Outcome(
            update: Self.update(provider: provider, balance: balance, polledAt: polledAt),
            succeeded: true
        )
    }

    /// A poll that ended without an amount. The record carries the reason so every surface, and
    /// the snapshot the widget reads, can say why instead of only that the balance is missing.
    private func report(
        _ reason: BalanceUnavailableReason,
        provider: String,
        polledAt: Date,
        succeeded: Bool
    ) -> Outcome {
        Outcome(
            update: .loaded(
                AccountBalance(
                    provider: provider,
                    amountUSD: nil,
                    lastPolledAt: polledAt,
                    unavailableReason: reason
                )
            ),
            succeeded: succeeded
        )
    }

    /// Only a refused key is worth naming on its own; every other answer Surge cannot use is an
    /// unexpected response, which the status code then identifies in the snapshot.
    private static func category(forStatus statusCode: Int) -> BalanceUnavailableReason.Category {
        statusCode == 401 || statusCode == 403 ? .keyRejected : .unexpectedResponse
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
