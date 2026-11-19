import Foundation
import SurgeCore

/// Forwards a pipeline's events to the state store and can hold them back while monitoring is
/// paused without finishing the stream, so resuming never loses a pipeline.
///
/// `@unchecked Sendable` is safe because every stored property is immutable and Sendable (the
/// stream, its continuation, the upstream stream and the actor that owns the pause state), and
/// the forwarding task only reads them.
final class PausablePipeline<Element: Sendable>: @unchecked Sendable {
    let stream: AsyncStream<Element>

    private let gate: PauseGate
    private let forwarder: Task<Void, Never>

    init(upstream: AsyncStream<Element>) {
        let gate = PauseGate()
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        self.gate = gate
        self.stream = stream
        forwarder = Task {
            for await element in upstream {
                await gate.waitWhilePaused()
                continuation.yield(element)
            }
            continuation.finish()
        }
    }

    deinit {
        forwarder.cancel()
    }

    func setPaused(_ paused: Bool) async {
        await gate.setPaused(paused)
    }
}

/// The pause flag a `PausablePipeline` waits on. Held in an actor so pausing and resuming never
/// race the forwarding task.
actor PauseGate {
    private var isPaused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func setPaused(_ paused: Bool) {
        isPaused = paused
        guard !paused else { return }
        let waiting = waiters
        waiters.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }

    func waitWhilePaused() async {
        guard isPaused else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

struct PausableSessionTailer: SessionTailing {
    let pipeline: PausablePipeline<TailerEvent>

    func events() -> AsyncStream<TailerEvent> {
        pipeline.stream
    }
}

struct PausableWorkerTraffic: WorkerTraffic {
    let pipeline: PausablePipeline<ProxyEvent>

    func events() -> AsyncStream<ProxyEvent> {
        pipeline.stream
    }
}

struct PausableWalletPolling: WalletPolling {
    let pipeline: PausablePipeline<BalanceUpdate>

    func updates() -> AsyncStream<BalanceUpdate> {
        pipeline.stream
    }
}
