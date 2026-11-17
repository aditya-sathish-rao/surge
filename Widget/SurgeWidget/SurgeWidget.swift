import SurgeCore
import SurgeUI
import SwiftUI
import WidgetKit

struct SurgeEntry: TimelineEntry {
    let date: Date
}

struct SurgeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SurgeEntry {
        SurgeEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SurgeEntry) -> Void) {
        completion(SurgeEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SurgeEntry>) -> Void) {
        completion(Timeline(entries: [SurgeEntry(date: .now)], policy: .never))
    }
}

struct SurgeWidgetView: View {
    var entry: SurgeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No agents running")
                .font(.headline)
            Text("Start Claude Code, or point workers at 127.0.0.1:8899.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SurgeWidget: Widget {
    let kind = "SurgeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SurgeTimelineProvider()) { entry in
            SurgeWidgetView(entry: entry)
        }
        .configurationDisplayName("Surge")
        .description(
            "See which coding agents and sub-agents are working, waiting for you, or stalled, "
                + "plus today's spend and account balances."
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
