import Foundation
import SurgeCore

/// One provider account Surge can poll for a prepaid balance.
///
/// A nil `balanceURL` means the provider exposes no balance endpoint. The poller
/// reports such an account as unavailable and makes no request for it.
public struct WalletAccount: Sendable, Equatable {
    public let provider: Provider
    public let balanceURL: URL?

    public init(provider: Provider, balanceURL: URL?) {
        self.provider = provider
        self.balanceURL = balanceURL
    }

    /// The three account rows Surge shows. Anthropic currently exposes no balance endpoint.
    public static let standard: [WalletAccount] = [
        WalletAccount(provider: .anthropic, balanceURL: nil),
        WalletAccount(provider: .deepseek, balanceURL: WalletEndpoints.deepSeekBalance),
        WalletAccount(provider: .openrouter, balanceURL: WalletEndpoints.openRouterKey),
    ]
}

public enum WalletEndpoints {
    public static let deepSeekBalance = URL(string: "https://api.deepseek.com/user/balance")
    public static let openRouterKey = URL(string: "https://openrouter.ai/api/v1/auth/key")
}

public struct WalletConfiguration: Sendable, Equatable {
    public static let defaultPollInterval: TimeInterval = 60
    public static let defaultRequestTimeout: TimeInterval = 15

    public let accounts: [WalletAccount]
    public let pollInterval: TimeInterval
    public let requestTimeout: TimeInterval
    public let backoff: BackoffPolicy

    /// `pollInterval` and `requestTimeout` are injected so tests never wait on a real clock.
    public init(
        accounts: [WalletAccount] = WalletAccount.standard,
        pollInterval: TimeInterval = WalletConfiguration.defaultPollInterval,
        requestTimeout: TimeInterval = WalletConfiguration.defaultRequestTimeout,
        backoff: BackoffPolicy? = nil
    ) {
        self.accounts = accounts
        self.pollInterval = pollInterval
        self.requestTimeout = requestTimeout
        self.backoff = backoff ?? .standard(pollInterval: pollInterval)
    }
}

/// Capped exponential backoff for a repeatedly failing poll.
public struct BackoffPolicy: Sendable, Equatable {
    public let initialDelay: TimeInterval
    public let multiplier: Double
    public let maximumDelay: TimeInterval

    public init(initialDelay: TimeInterval, multiplier: Double = 2, maximumDelay: TimeInterval) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maximumDelay = maximumDelay
    }

    /// A provider that keeps failing is retried after the poll interval, then at doubling
    /// delays up to eight intervals.
    public static func standard(pollInterval: TimeInterval) -> BackoffPolicy {
        BackoffPolicy(initialDelay: pollInterval, maximumDelay: pollInterval * 8)
    }

    /// Delay before the next attempt. `failures` is the number of consecutive failed polls.
    public func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 1 else { return capped(initialDelay) }
        let exponent = min(failures - 1, 16)
        return capped(initialDelay * pow(multiplier, Double(exponent)))
    }

    private func capped(_ value: TimeInterval) -> TimeInterval {
        min(value, maximumDelay)
    }
}
