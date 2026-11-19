import Foundation
import SurgeCore
import WidgetKit

/// The one background owner of the snapshot file and the widget reload policy.
///
/// It lives in the app target, never in the state store: the store stays a pure merge of pipeline
/// events. Writes are coalesced to one every five seconds and reloads to one every sixty.
actor SnapshotWriter {
    private let store: SnapshotFileStore
    private let clock: @Sendable () -> Date
    private var coalescer = WriteCoalescer()
    private var reloadPolicy = WidgetReloadPolicy()
    private var latest: SurgeSnapshot?
    private var hasPendingWrite = false
    private var isDraining = false

    init(
        store: SnapshotFileStore = SnapshotFileStore(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.clock = clock
    }

    func submit(_ snapshot: SurgeSnapshot) {
        latest = snapshot
        hasPendingWrite = true
        reloadPolicy.note(workspaces: snapshot.workspaces, balances: snapshot.balances)
        if !isDraining {
            isDraining = true
            Task { await self.drain() }
        }
    }

    /// The user is looking, so the widget is worth refreshing within the one-minute ceiling.
    func noteSurfaceOpened() {
        reloadPolicy.notePopoverOpened()
        reloadIfAllowed()
    }

    private func drain() async {
        while hasPendingWrite {
            hasPendingWrite = false
            if case .wait(let delay) = coalescer.submit(at: clock()) {
                try? await Task.sleep(for: .seconds(delay))
            }
            coalescer.didWrite(at: clock())
            if let snapshot = latest {
                try? store.write(snapshot)
            }
            reloadIfAllowed()
        }
        isDraining = false
    }

    private func reloadIfAllowed() {
        guard reloadPolicy.shouldReload(at: clock()) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: SnapshotLocation.widgetKind)
    }
}
