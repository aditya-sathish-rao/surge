import SurgeCore
import SurgeUI
import SwiftUI
import WidgetKit

/// The widget body: one size, one layout, one click target. Cards stay dark in both appearances,
/// so the background is the card token inside `ContainerRelativeShape` (PRD 7.3, design system).
struct SurgeWidgetView: View {
    let entry: SurgeEntry
    @Environment(\.widgetFamily) private var family

    private var layout: WidgetLayout {
        switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                ContainerRelativeShape().fill(SurgeColors.card)
            }
            .widgetURL(panelURL)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch layout {
            case .small:
                SmallWidgetView(snapshot: snapshot, filter: entry.filter, now: entry.date)
            case .medium:
                MediumWidgetView(snapshot: snapshot, filter: entry.filter, now: entry.date)
            case .large:
                LargeWidgetView(snapshot: snapshot, filter: entry.filter, now: entry.date)
            }
        } else {
            WidgetPlaceholderView(layout: layout)
        }
    }

    private var panelURL: URL {
        guard let snapshot = entry.snapshot else {
            return WidgetDeepLink.panelURL(workspaceID: entry.filter.workspaceID)
        }
        return WidgetDeepLink.panelURL(
            workspaceID: WidgetDeepLink.targetWorkspace(in: snapshot, filter: entry.filter, layout: layout)
        )
    }
}
