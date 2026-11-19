import Foundation
import SurgeCore
import Testing

@testable import SurgeStateStore

/// A clock tests move by hand.
///
/// `@unchecked Sendable` is safe because the only mutable state is guarded by an `NSLock` and the
/// stored value is a plain `Date`.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        self.current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

/// One synthetic pipeline stream a test drives by hand.
struct TestPipeline<Event: Sendable>: Sendable {
    let stream: AsyncStream<Event>
    let continuation: AsyncStream<Event>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }
}

struct FakeTailer: SessionTailing {
    let pipeline: TestPipeline<TailerEvent>

    func events() -> AsyncStream<TailerEvent> { pipeline.stream }
}

struct FakeProxy: WorkerTraffic {
    let pipeline: TestPipeline<ProxyEvent>

    func events() -> AsyncStream<ProxyEvent> { pipeline.stream }
}

struct FakeWallets: WalletPolling {
    let pipeline: TestPipeline<BalanceUpdate>

    func updates() -> AsyncStream<BalanceUpdate> { pipeline.stream }
}

struct TestPipelines {
    let tailer: TestPipeline<TailerEvent>
    let proxy: TestPipeline<ProxyEvent>
    let wallets: TestPipeline<BalanceUpdate>
    let store: SurgeStateStore
}

/// Shared inputs for state store tests. Pricing mirrors the bundled table so expected costs and
/// stall thresholds are the real ones.
enum StoreFixture {
    static let referenceDate = SurgeFixtures.referenceDate
    static let projectPath = "/Users/dev/code/surge"

    static let pricing = PricingTable(models: [
        "claude-sonnet": ModelPricing(
            contextWindow: 200_000,
            inputPerMillion: 3.00,
            outputPerMillion: 15.00,
            cacheReadPerMillion: 0.30
        ),
        "deepseek-chat": ModelPricing(
            contextWindow: 128_000,
            inputPerMillion: 0.27,
            outputPerMillion: 1.10,
            cacheReadPerMillion: 0.07
        ),
        "deepseek-reasoner": ModelPricing(
            contextWindow: 128_000,
            inputPerMillion: 0.55,
            outputPerMillion: 2.19,
            cacheReadPerMillion: 0.14,
            stallThresholdSeconds: 300
        ),
        "openrouter-auto": ModelPricing(
            contextWindow: 128_000,
            inputPerMillion: 0.50,
            outputPerMillion: 1.50,
            cacheReadPerMillion: 0.10
        ),
    ])

    static func date(_ seconds: TimeInterval) -> Date {
        referenceDate.addingTimeInterval(seconds)
    }

    static func pipelines(
        clock: TestClock,
        pricing: PricingTable = StoreFixture.pricing,
        catalog: ModelCatalog = .empty,
        thresholds: BalanceThresholds = BalanceThresholds(),
        billing: BillingConfiguration = .standard
    ) -> TestPipelines {
        let tailer = TestPipeline<TailerEvent>()
        let proxy = TestPipeline<ProxyEvent>()
        let wallets = TestPipeline<BalanceUpdate>()
        let store = SurgeStateStore(
            tailer: FakeTailer(pipeline: tailer),
            proxy: FakeProxy(pipeline: proxy),
            wallets: FakeWallets(pipeline: wallets),
            pricing: pricing,
            catalog: catalog,
            balanceThresholds: thresholds,
            billing: billing,
            clock: { clock.now }
        )
        return TestPipelines(tailer: tailer, proxy: proxy, wallets: wallets, store: store)
    }

    static func session(
        _ id: String = "session-a",
        path: String = StoreFixture.projectPath,
        model: String = "claude-sonnet",
        provider: String = "anthropic",
        parent: String? = nil,
        harness: HarnessIdentity? = nil,
        at offset: TimeInterval = 0
    ) -> SessionDescriptor {
        SessionDescriptor(
            id: id,
            projectPath: path,
            provider: provider,
            modelName: model,
            maxContextWindow: 200_000,
            occurredAt: date(offset),
            harness: harness
                ?? HarnessIdentity(kind: .claudeCode, version: "2.0.31", sessionID: id, transport: .jsonl),
            parentSessionID: parent
        )
    }

    static func worker(
        _ id: String = "worker-1",
        path: String = StoreFixture.projectPath,
        model: String = "deepseek-chat",
        provider: String = "deepseek",
        parent: String? = "session-a",
        at offset: TimeInterval = 0
    ) -> WorkerDescriptor {
        WorkerDescriptor(
            id: id,
            provider: provider,
            modelName: model,
            projectPath: path,
            parentSessionID: parent,
            occurredAt: date(offset)
        )
    }

    static func turn(
        _ sessionID: String = "session-a",
        model: String = "claude-sonnet",
        input: Int = 0,
        output: Int = 0,
        cache: Int = 0,
        context: Int = 0,
        at offset: TimeInterval,
        eventID: String? = nil,
        harnessReportedCostUSD: Double? = nil,
        turnProviderReportedUSD: Double? = nil,
        turnHarnessReportedUSD: Double? = nil
    ) -> TurnAppended {
        TurnAppended(
            sessionID: sessionID,
            modelName: model,
            inputTokens: input,
            outputTokens: output,
            cacheHitTokens: cache,
            currentContextTokens: context,
            occurredAt: date(offset),
            eventID: eventID,
            harnessReportedCostUSD: harnessReportedCostUSD,
            turnProviderReportedUSD: turnProviderReportedUSD,
            turnHarnessReportedUSD: turnHarnessReportedUSD
        )
    }

    static func usage(
        _ workerID: String = "worker-1",
        model: String = "deepseek-chat",
        provider: String = "deepseek",
        input: Int = 0,
        output: Int = 0,
        cache: Int = 0,
        context: Int = 0,
        at offset: TimeInterval,
        reportedCostUSD: Double? = nil
    ) -> ProxyUsage {
        ProxyUsage(
            workerID: workerID,
            provider: provider,
            modelName: model,
            inputTokens: input,
            outputTokens: output,
            cacheHitTokens: cache,
            currentContextTokens: context,
            occurredAt: date(offset),
            reportedCostUSD: reportedCostUSD
        )
    }

    static func balance(
        _ provider: String = "deepseek",
        amount: Double,
        at offset: TimeInterval = 0
    ) -> AccountBalance {
        AccountBalance(provider: provider, amountUSD: amount, lastPolledAt: date(offset))
    }

    static func unavailableBalance(
        _ provider: String = "deepseek",
        reason: BalanceUnavailableReason.Category = .keyUnavailable,
        at offset: TimeInterval = 0
    ) -> AccountBalance {
        AccountBalance(
            provider: provider,
            amountUSD: nil,
            lastPolledAt: date(offset),
            unavailableReason: BalanceUnavailableReason(reason)
        )
    }
}

/// Waits for the first published tree that matches. The change stream yields the current tree
/// immediately, so a store that already holds the expected state returns without waiting.
func firstTree(
    from store: SurgeStateStore,
    matching predicate: @Sendable (StoreTree) -> Bool
) async -> StoreTree? {
    for await tree in await store.changes() where predicate(tree) {
        return tree
    }
    return nil
}
