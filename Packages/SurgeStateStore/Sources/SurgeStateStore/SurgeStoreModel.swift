import Foundation
import Observation
import SurgeCore

/// One workspace the UI observes.
///
/// A row is kept alive while its workspace exists and only mutated when its content changes, so
/// a view that reads a row re-renders for that row alone. The parent list only changes when the
/// set of workspaces or their order changes.
@MainActor
@Observable
public final class WorkspaceRow: Identifiable {
    public let id: UUID
    public private(set) var workspace: WorkspaceSession
    public private(set) var attentionCount: Int

    init(workspace: WorkspaceSession, attentionCount: Int) {
        self.id = workspace.id
        self.workspace = workspace
        self.attentionCount = attentionCount
    }

    func update(with workspace: WorkspaceSession, attentionCount: Int) {
        if self.workspace != workspace { self.workspace = workspace }
        if self.attentionCount != attentionCount { self.attentionCount = attentionCount }
    }
}

/// The Observation bridge between the store actor and SwiftUI.
///
/// The model mirrors the store's published tree on the main actor. Views read `workspaces` and
/// the row objects; the store itself stays off the main actor and never imports SwiftUI.
@MainActor
@Observable
public final class SurgeStoreModel {
    public private(set) var workspaces: [WorkspaceRow] = []
    public private(set) var balances: [AccountBalance] = []
    public private(set) var attentionCount = 0
    public private(set) var orchestratorCount = 0
    public private(set) var workerCount = 0
    public private(set) var totalSpendUSD = 0.0
    public private(set) var generatedAt: Date?

    private let store: SurgeStateStore
    private var observation: Task<Void, Never>?

    public init(store: SurgeStateStore) {
        self.store = store
    }

    /// Starts mirroring the store. The first tree arrives immediately.
    public func start() {
        guard observation == nil else { return }
        let store = self.store
        observation = Task { [weak self, store] in
            for await tree in await store.changes() {
                guard let self else { return }
                self.apply(tree)
            }
        }
    }

    public func stop() {
        observation?.cancel()
        observation = nil
    }

    /// Recomputes derived state so stall timers advance between pipeline events.
    public func refresh() async {
        await store.refresh()
    }

    /// Mirrors one tree. The observation loop calls this; previews and tests may call it too.
    public func apply(_ tree: StoreTree) {
        updateRows(from: tree)
        if balances != tree.balances { balances = tree.balances }
        if attentionCount != tree.attentionCount { attentionCount = tree.attentionCount }
        if orchestratorCount != tree.orchestratorCount { orchestratorCount = tree.orchestratorCount }
        if workerCount != tree.workerCount { workerCount = tree.workerCount }
        if totalSpendUSD != tree.totalSpendUSD { totalSpendUSD = tree.totalSpendUSD }
        if generatedAt != tree.generatedAt { generatedAt = tree.generatedAt }
    }

    private func updateRows(from tree: StoreTree) {
        let existing = workspaces
        var reusable: [UUID: WorkspaceRow] = [:]
        for row in existing {
            reusable[row.id] = row
        }

        var rows: [WorkspaceRow] = []
        rows.reserveCapacity(tree.workspaces.count)
        var structureChanged = existing.count != tree.workspaces.count
        for (index, workspace) in tree.workspaces.enumerated() {
            let count = tree.attentionCount(forWorkspace: workspace.id)
            let row: WorkspaceRow
            if let reused = reusable.removeValue(forKey: workspace.id) {
                reused.update(with: workspace, attentionCount: count)
                row = reused
            } else {
                row = WorkspaceRow(workspace: workspace, attentionCount: count)
                structureChanged = true
            }
            rows.append(row)
            if existing.indices.contains(index), existing[index].id != workspace.id {
                structureChanged = true
            }
        }
        if structureChanged { workspaces = rows }
    }
}
