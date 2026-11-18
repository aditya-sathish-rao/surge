import Foundation
import SurgeCore

/// The single actor that owns the canonical agent tree.
///
/// Each pipeline runs in its own `Task` consuming its own `AsyncStream` and merging through
/// `apply(_:)`, so actor isolation serializes every change and no lock is needed anywhere. The
/// store depends on the frozen `SurgeCore` protocols only; the real tailer, proxy and poller are
/// injected at launch.
///
/// Every publish recomputes derived state: stall detection against the injected clock and the
/// model's threshold, PRD 6.2 sort order, workspace cost totals, attention counts, and the
/// ten-minute Done window. The UI reads the result and never derives any of it.
public actor SurgeStateStore {
    /// The bundled pricing table, or an empty table when the resource is missing.
    public static let defaultPricing: PricingTable =
        (try? PricingTable.bundled()) ?? PricingTable(models: [:])

    private let tailer: any SessionTailing
    private let proxy: any WorkerTraffic
    private let wallets: any WalletPolling
    let pricing: PricingTable
    let balanceThresholds: BalanceThresholds
    private let clock: @Sendable () -> Date

    var workspaceRecords: [String: WorkspaceRecord] = [:]
    var balanceRecords: [String: AccountBalance] = [:]
    var observers: [UUID: AsyncStream<StoreTree>.Continuation] = [:]
    var pipelineTasks: [Task<Void, Never>] = []

    /// The current tree. Reading it does not advance timers; call `refresh()` to do that.
    public internal(set) var tree: StoreTree

    /// - Parameters:
    ///   - pricing: Supplies the context window and stall threshold per model.
    ///   - balanceThresholds: The Low and Empty thresholds, so Settings can override them.
    ///   - clock: Injected so stall detection and Done expiry are deterministic in tests.
    public init(
        tailer: any SessionTailing,
        proxy: any WorkerTraffic,
        wallets: any WalletPolling,
        pricing: PricingTable = SurgeStateStore.defaultPricing,
        balanceThresholds: BalanceThresholds = BalanceThresholds(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tailer = tailer
        self.proxy = proxy
        self.wallets = wallets
        self.pricing = pricing
        self.balanceThresholds = balanceThresholds
        self.clock = clock
        self.tree = StoreTree.empty(at: clock(), balanceThresholds: balanceThresholds)
    }

    /// Starts one task per pipeline. Each stream is consumed in order, so events on one pipeline
    /// cannot overtake each other; merging across pipelines is ordered by the actor.
    public func start() {
        guard pipelineTasks.isEmpty else { return }
        let tailerEvents = tailer.events()
        let proxyEvents = proxy.events()
        let walletUpdates = wallets.updates()
        pipelineTasks = [
            Task { [weak self] in
                for await event in tailerEvents {
                    guard let self else { return }
                    await self.apply(event)
                }
            },
            Task { [weak self] in
                for await event in proxyEvents {
                    guard let self else { return }
                    await self.apply(event)
                }
            },
            Task { [weak self] in
                for await update in walletUpdates {
                    guard let self else { return }
                    await self.apply(update)
                }
            },
        ]
    }

    public func stop() {
        for task in pipelineTasks { task.cancel() }
        pipelineTasks.removeAll()
    }

    /// The current tree, then every later change. A new subscriber gets the latest tree at once.
    public func changes() -> AsyncStream<StoreTree> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<StoreTree>.makeStream()
        observers[id] = continuation
        continuation.yield(tree)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    /// Recomputes derived state against the clock. The app calls this once a second so stall
    /// timers flip even when no pipeline event has arrived.
    public func refresh() {
        publish(now: clock())
    }

    public func apply(_ event: TailerEvent) {
        switch event {
        case .sessionAppeared(let descriptor):
            merge(session: descriptor)
        case .turnAppended(let turn):
            merge(turn: turn)
        case .sessionEnded(let sessionID, let occurredAt):
            merge(sessionEnded: sessionID, at: occurredAt)
        }
        publish(now: clock())
    }

    public func apply(_ event: ProxyEvent) {
        switch event {
        case .workerAppeared(let descriptor):
            merge(worker: descriptor)
        case .usage(let usage):
            merge(usage: usage)
        }
        publish(now: clock())
    }

    public func apply(_ update: BalanceUpdate) {
        merge(balance: update)
        publish(now: clock())
    }

    /// Records a state the token traffic cannot carry, such as a permission prompt or a
    /// compaction. Stall detection ignores `waitingForYou`, and `.stalled` is derived, so
    /// recording it does nothing.
    public func record(_ status: AgentStatus, for agentID: String, at occurredAt: Date) {
        merge(status: status, for: agentID, at: occurredAt)
        publish(now: clock())
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
