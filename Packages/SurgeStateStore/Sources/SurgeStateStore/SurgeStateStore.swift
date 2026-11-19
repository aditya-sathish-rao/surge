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
    /// The live model numbers the tree is priced and measured against.
    private(set) var priceBook: PriceBook
    let balanceThresholds: BalanceThresholds
    private let clock: @Sendable () -> Date

    var workspaceRecords: [String: WorkspaceRecord] = [:]
    var balanceRecords: [String: AccountBalance] = [:]
    var observers: [UUID: AsyncStream<StoreTree>.Continuation] = [:]
    var pipelineTasks: [Task<Void, Never>] = []

    /// The current tree. Reading it does not advance timers; call `refresh()` to do that.
    public internal(set) var tree: StoreTree

    /// - Parameters:
    ///   - pricing: Supplies the last-known context window, stall threshold and rates per model.
    ///   - catalog: The provider's own model list, which wins over `pricing` wherever it knows more.
    ///   - balanceThresholds: The Low and Empty thresholds, so Settings can override them.
    ///   - clock: Injected so stall detection and Done expiry are deterministic in tests.
    public init(
        tailer: any SessionTailing,
        proxy: any WorkerTraffic,
        wallets: any WalletPolling,
        pricing: PricingTable = SurgeStateStore.defaultPricing,
        catalog: ModelCatalog = .empty,
        balanceThresholds: BalanceThresholds = BalanceThresholds(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.tailer = tailer
        self.proxy = proxy
        self.wallets = wallets
        self.pricing = pricing
        priceBook = PriceBook(catalog: catalog, fallback: pricing)
        self.balanceThresholds = balanceThresholds
        self.clock = clock
        self.tree = StoreTree.empty(at: clock(), balanceThresholds: balanceThresholds)
    }

    /// Replaces the model numbers after a fresh fetch. Context windows and costs recompute on the
    /// next publish, so a larger window stops the context meter understating immediately.
    public func updateCatalog(_ catalog: ModelCatalog) {
        priceBook = PriceBook(catalog: catalog, fallback: pricing)
        for projectPath in workspaceRecords.keys {
            guard var workspace = workspaceRecords[projectPath] else { continue }
            for id in workspace.agents.keys {
                guard var agent = workspace.agents[id] else { continue }
                if let window = priceBook.contextWindow(forModel: agent.modelName) {
                    agent.maxContextWindow = window
                }
                recoverUnpricedCost(&agent)
                workspace.agents[id] = agent
            }
            workspaceRecords[projectPath] = workspace
        }
        publish(now: clock())
    }

    /// A model that was unknown when its tokens arrived can be priced once a model list names it.
    /// Only agents with no figure at all are repriced, so reported and derived money is never
    /// overwritten by a local estimate.
    private func recoverUnpricedCost(_ agent: inout AgentRecord) {
        guard agent.unpricedTokens > 0, agent.costBySource.totalUSD == 0,
            let estimate = priceBook.estimatedCostUSD(
                forModel: agent.modelName,
                inputTokens: agent.inputTokens,
                outputTokens: agent.outputTokens,
                cacheHitTokens: agent.cacheHitTokens
            )
        else { return }
        agent.costBySource.add(estimate, source: .estimated)
        agent.unpricedTokens = 0
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
