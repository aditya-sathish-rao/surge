import Foundation

/// Time and waiting, injected so the poller can be driven without a real clock.
public protocol WalletScheduler: Sendable {
    func now() async -> Date
    func sleep(for duration: TimeInterval) async throws
}

public struct SystemWalletScheduler: WalletScheduler {
    public init() {}

    public func now() async -> Date {
        Date()
    }

    public func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(duration))
    }
}
