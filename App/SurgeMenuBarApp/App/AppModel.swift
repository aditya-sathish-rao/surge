import AppKit
import Foundation
import Observation
import SurgeCore
import SurgeIngestProxy
import SurgeIngestTailer
import SurgeStateStore
import SurgeUI
import SurgeWallets

/// Owns the pipelines, the state store, the snapshot writer, the notifications and the panel.
///
/// The store is the only place the agent tree is mutated; this model observes its published tree
/// and turns it into what the app shows, writes and announces.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings: SurgeSettings
    /// The one place the app reads and writes provider keys. Only the app target touches it.
    let keys: KeychainWalletKeys
    private(set) var storeModel: SurgeStoreModel
    private(set) var now: Date
    private(set) var isPaused = false
    private(set) var ledger: DailySpendLedger
    private(set) var throughput = ThroughputTracker()

    private let clock: @Sendable () -> Date
    private let tailer: TranscriptTailer
    private let proxy: ProxyServer
    private let store: SurgeStateStore
    private let catalogStore: ModelCatalogStore
    private let writer: SnapshotWriter
    private let notifications = NotificationCenterPoster()
    private let tailerGate: PausablePipeline<TailerEvent>
    private let proxyGate: PausablePipeline<ProxyEvent>
    private let walletGate: PausablePipeline<BalanceUpdate>
    private var planner = NotificationPlanner()
    private var observation: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var panelControllerInstance: PanelController?

    private init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
        let startedAt = clock()
        now = startedAt

        let settings = SurgeSettings()
        self.settings = settings

        let keys = KeychainWalletKeys()
        self.keys = keys
        let tailer = TranscriptTailer(clock: clock)
        let proxy = ProxyServer(clock: clock)
        // A subscription has no balance endpoint to poll. Its row comes from its window instead.
        let walletAccounts = WalletAccount.standard.filter {
            !settings.quotaAccountIDs.contains($0.provider.rawValue)
        }
        let wallets = WalletPoller(
            configuration: WalletConfiguration(accounts: walletAccounts),
            keys: keys
        )
        let catalogStore = ModelCatalogStore(directory: SnapshotLocation.local().directory)
        let tailerGate = PausablePipeline(upstream: tailer.events())
        let proxyGate = PausablePipeline(upstream: proxy.events())
        let walletGate = PausablePipeline(upstream: wallets.updates())
        let pricing = PricingOverrides.applying(settings.stallOverrides, to: SurgeStateStore.defaultPricing)
        let store = SurgeStateStore(
            tailer: PausableSessionTailer(pipeline: tailerGate),
            proxy: PausableWorkerTraffic(pipeline: proxyGate),
            wallets: PausableWalletPolling(pipeline: walletGate),
            pricing: pricing,
            catalog: catalogStore.load(),
            balanceThresholds: settings.balanceThresholds,
            billing: settings.billingConfiguration(),
            clock: clock
        )

        self.tailer = tailer
        self.proxy = proxy
        self.tailerGate = tailerGate
        self.proxyGate = proxyGate
        self.walletGate = walletGate
        self.store = store
        self.catalogStore = catalogStore
        storeModel = SurgeStoreModel(store: store)
        writer = SnapshotWriter(clock: clock)
        ledger = DailySpendLedger(
            seed: SnapshotFileStore().read(),
            accounts: settings.billingConfiguration().accounts
        )
    }

    // MARK: - Reading

    var workspaces: [WorkspaceSession] {
        storeModel.workspaces.map(\.workspace)
    }

    var readout: MenuBarReadout {
        MenuBarReadout(
            orchestrators: storeModel.orchestratorCount,
            workers: storeModel.workerCount,
            spend: todaySpendFigure,
            attentionCount: storeModel.attentionCount
        )
    }

    var todaySpendUSD: Double {
        ledger.todayTotal(at: now)
    }

    /// Today's total with its label. The number is never shown without it.
    var todaySpendFigure: SpendFigure {
        ledger.todayFigure(at: now)
    }

    var todaySpendSource: CostSource {
        ledger.todaySource(at: now)
    }

    var todaySpendPoint: DailySpendPoint {
        ledger.todayPoint(at: now)
    }

    var dailySpend: [DailySpendPoint] {
        ledger.lastDays(DailySpendLedger.retentionDays, at: now)
    }

    var throughputSamples: [ThroughputSample] {
        throughput.samples
    }

    func tokensPerSecond(for agentID: String) -> Double? {
        throughput.rate(for: agentID)
    }

    func isMuted(_ agentID: String) -> Bool {
        settings.mutedAgentIDs.contains(agentID)
    }

    func toggleMute(_ agentID: String) {
        settings.toggleMuted(agentID)
    }

    // MARK: - Lifecycle

    func start() {
        guard observation == nil else { return }
        settings.onShortcutChanged = { [weak self] in
            self?.installShortcut()
        }
        settings.onBillingChanged = { [weak self] in
            self?.applyBilling()
        }
        installShortcut()

        observation = Task { [weak self] in
            guard let self else { return }
            let changes = await self.store.changes()
            for await tree in changes {
                await self.apply(tree)
            }
        }
        Task {
            await self.store.start()
            await self.proxy.start()
            await self.tailer.start()
        }
        startTicker()
        startModelCatalog()
        Task { await notifications.requestAuthorization() }
    }

    /// Hands the store a changed account, binding or window so sessions already on screen resolve
    /// against it at once instead of waiting for a relaunch.
    private func applyBilling() {
        let configuration = settings.billingConfiguration()
        Task { [store] in
            await store.updateBilling(configuration)
        }
    }

    /// Fetches the providers' own model lists, caches them and hands them to the store. A failed
    /// fetch leaves the cached numbers in place, so an offline launch never falls back to a
    /// frozen table that does not know the model.
    func refreshModelCatalog() async {
        let fetched = await ModelCatalogClient(keys: keys).fetch()
        guard fetched.isEmpty == false else { return }
        let merged = catalogStore.load().merging(fetched)
        catalogStore.save(merged)
        await store.updateCatalog(merged)
    }

    private func startModelCatalog() {
        Task { [weak self] in
            await self?.refreshModelCatalog()
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(21_600))
                await self?.refreshModelCatalog()
            }
        }
    }

    /// Stops the store seeing new pipeline events without finishing any pipeline stream.
    func togglePause() async {
        isPaused.toggle()
        let paused = isPaused
        await tailerGate.setPaused(paused)
        await proxyGate.setPaused(paused)
        await walletGate.setPaused(paused)
        if !paused {
            now = clock()
        }
    }

    func surfaceOpened() {
        let writer = writer
        Task { await writer.noteSurfaceOpened() }
    }

    // MARK: - Panel and deep links

    func detach(filter: WorkspaceFilter) {
        panelController.show(filter: filter)
        surfaceOpened()
    }

    func togglePanel() {
        panelController.toggle(filter: .all)
        surfaceOpened()
    }

    /// `surge://panel` or `surge://panel?workspace=<uuid>` opens the panel, optionally filtered.
    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "surge" else { return }
        var filter = WorkspaceFilter.all
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let raw = components?.queryItems?.first(where: { $0.name == "workspace" })?.value
        if let raw, let id = UUID(uuidString: raw) {
            filter = .workspace(id)
        }
        detach(filter: filter)
    }

    private var panelController: PanelController {
        if let panelControllerInstance {
            return panelControllerInstance
        }
        let controller = PanelController(model: self)
        panelControllerInstance = controller
        return controller
    }

    // MARK: - Store updates

    private func apply(_ tree: StoreTree) async {
        storeModel.apply(tree)
        let now = clock()
        self.now = now
        ledger.record(workspaces: tree.workspaces, balances: tree.balances, at: now)
        throughput.record(workspaces: tree.workspaces, at: now)
        let alerts = planner.evaluate(
            agents: Self.alertStates(in: tree.workspaces),
            options: settings.notificationOptions,
            now: now
        )
        for alert in alerts {
            notifications.post(alert)
        }
        let snapshot = SurgeSnapshot(
            generatedAt: tree.generatedAt,
            workspaces: tree.workspaces,
            balances: tree.balances,
            dailySpend: ledger.lastDays(7, at: now)
        )
        await writer.submit(snapshot)
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard !self.isPaused else { continue }
                await self.store.refresh()
                self.now = self.clock()
                self.throughput.record(workspaces: self.workspaces, at: self.now)
            }
        }
    }

    private func installShortcut() {
        GlobalHotKey.shared.register(settings.shortcut) { [weak self] in
            self?.togglePanel()
        }
    }

    private static func alertStates(in workspaces: [WorkspaceSession]) -> [AgentAlertState] {
        workspaces.flatMap { workspace in
            ([workspace.orchestrator] + workspace.workers).map { agent in
                AgentAlertState(
                    id: agent.id,
                    modelName: AgentRowPresentation.displayName(forModel: agent.modelName),
                    workspaceName: workspace.name,
                    status: agent.status
                )
            }
        }
    }
}
