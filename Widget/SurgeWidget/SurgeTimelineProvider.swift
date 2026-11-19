import Foundation
import SurgeCore
import WidgetKit

/// What one widget reload carries: the snapshot as written, or nothing when the file is missing or
/// unreadable, which draws the placeholder.
struct SurgeEntry: TimelineEntry {
    let date: Date
    let snapshot: SurgeSnapshot?
    let filter: WidgetWorkspaceFilter

    static func placeholder(now: Date = .now) -> SurgeEntry {
        SurgeEntry(date: now, snapshot: nil, filter: .all)
    }
}

struct SurgeTimelineProvider: AppIntentTimelineProvider {
    /// A widget with no data asks for a new timeline at the same cadence a snapshot goes stale, so
    /// the freshness caption and any missed app reload still land within the system budget.
    static let refreshInterval: TimeInterval = 300

    func placeholder(in context: Context) -> SurgeEntry {
        .placeholder()
    }

    func snapshot(for configuration: SurgeWidgetConfigurationIntent, in context: Context) async -> SurgeEntry {
        guard !context.isPreview else { return placeholder(in: context) }
        return entry(for: configuration)
    }

    func timeline(
        for configuration: SurgeWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<SurgeEntry> {
        let entry = entry(for: configuration)
        let next = Date.now.addingTimeInterval(Self.refreshInterval)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: SurgeWidgetConfigurationIntent) -> SurgeEntry {
        let filter = WidgetWorkspaceFilter(workspaceID: configuration.workspace?.id)
        switch SnapshotStore.load(from: SnapshotLocation.fileURL()) {
        case .snapshot(let snapshot):
            return SurgeEntry(date: .now, snapshot: snapshot, filter: filter)
        case .unavailable:
            return SurgeEntry(date: .now, snapshot: nil, filter: filter)
        }
    }
}
