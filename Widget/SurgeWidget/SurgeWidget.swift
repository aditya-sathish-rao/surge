import SurgeCore
import SurgeUI
import SwiftUI
import WidgetKit

/// One widget, "Surge", in Small, Medium and Large. It only ever reads the snapshot file the app
/// writes: no pipeline, no state store, no networking.
struct SurgeWidget: Widget {
    let kind = "SurgeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SurgeWidgetConfigurationIntent.self,
            provider: SurgeTimelineProvider()
        ) { entry in
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
