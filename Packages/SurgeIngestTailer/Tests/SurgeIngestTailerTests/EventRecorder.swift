import Foundation
import SurgeCore
import os

/// Collects events from the tailer stream so tests can wait for a count without cancelling
/// the shared stream, and can assert that nothing arrived inside a short window.
final class EventRecorder: Sendable {
    private let storage = OSAllocatedUnfairLock<[TailerEvent]>(initialState: [])
    private let consumer: Task<Void, Never>

    init(_ stream: AsyncStream<TailerEvent>) {
        let storage = storage
        consumer = Task {
            for await event in stream {
                storage.withLock { $0.append(event) }
            }
        }
    }

    deinit {
        consumer.cancel()
    }

    func wait(forCount count: Int, timeout: Duration = .seconds(5)) async -> [TailerEvent] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let snapshot = storage.withLock { $0 }
            if snapshot.count >= count {
                return snapshot
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return storage.withLock { $0 }
    }

    func recordedEvents() -> [TailerEvent] {
        storage.withLock { $0 }
    }
}

func turns(in events: [TailerEvent]) -> [TurnAppended] {
    events.compactMap { event in
        if case .turnAppended(let turn) = event {
            return turn
        }
        return nil
    }
}

func appeared(in events: [TailerEvent]) -> [SessionDescriptor] {
    events.compactMap { event in
        if case .sessionAppeared(let descriptor) = event {
            return descriptor
        }
        return nil
    }
}

func ended(in events: [TailerEvent]) -> [String] {
    events.compactMap { event in
        if case .sessionEnded(let sessionID, _) = event {
            return sessionID
        }
        return nil
    }
}
