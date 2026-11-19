import Foundation

/// Keeps snapshot writes to at most one every five seconds.
///
/// The first submission after a quiet spell writes straight away. Every change inside the window
/// is folded into one trailing write of the latest state when the window closes.
struct WriteCoalescer: Equatable {
    static let minimumInterval: TimeInterval = 5

    enum Action: Equatable {
        case writeNow
        case wait(TimeInterval)
    }

    private(set) var lastWriteAt: Date?

    mutating func submit(at now: Date) -> Action {
        guard let lastWriteAt else { return .writeNow }
        let elapsed = now.timeIntervalSince(lastWriteAt)
        guard elapsed < Self.minimumInterval else { return .writeNow }
        return .wait(Self.minimumInterval - elapsed)
    }

    mutating func didWrite(at now: Date) {
        lastWriteAt = now
    }
}
