import SurgeCore
import SurgeUI
import SwiftUI

/// The widget's type scale, spacing and status hues, built from `SurgeCore` tokens.
///
/// Nothing here is smaller than the 11 pt widget floor. `SurgeUI`'s status style is internal and its
/// agent row is a two-line, 44 pt row that a Medium widget cannot fit four of, so the widget repeats
/// the two-hue split of the design system here and composes everything else from `SurgeUI`.
enum WidgetStyle {
    static let heading = SurgeTypography.sans(11, weight: .medium)
    static let rowName = SurgeTypography.sans(12, weight: .medium)
    /// The Small widget's one agent is the whole point of that size, so its name sits a step above
    /// the status and provenance lines under it.
    static let heroName = SurgeTypography.sans(13, weight: .medium)
    static let rowValue = SurgeTypography.sans(11)
    static let meta = SurgeTypography.widgetMeta
    static let readout = SurgeTypography.readoutL
    static let readoutTracking = SurgeTypography.displayTracking(forSize: 28)
    static let balanceName = SurgeTypography.sans(11)
    static let balanceAmount = SurgeTypography.sans(12, weight: .medium)

    static let rowSpacing: CGFloat = 5
    /// The Medium layout is the tight one: four rows, balances and the freshness caption at 158 pt.
    static let compactSpacing: CGFloat = 2
    static let fuseWidth: CGFloat = 60
    /// The status column is at least this wide: 92 pt fits every state word and a stalled timer up to
    /// three-digit hours at 11 pt, and a longer timer widens the column when the row has room.
    static let valueWidth: CGFloat = 92
    static let miniFuseLength: CGFloat = 34
    static let miniFuseWidth: CGFloat = 10
    static let skeletonOpacity: Double = 0.12
    static let skeletonOpacityIncreasedContrast: Double = 0.24
    static let maxLargeRows = 5

    /// Waiting for you owns orange, stalled owns coral, a healthy agent is drawn in white.
    static func statusColor(for status: AgentStatus, contrast: ColorSchemeContrast) -> Color {
        switch status {
        case .waitingForYou:
            SurgeColors.caution
        case .stalled:
            SurgeColors.alert
        case .working:
            SurgeInk.primary()
        case .compacting, .done, .noSignal:
            SurgeInk.secondary(contrast)
        case .idle:
            SurgeInk.tertiary(contrast)
        }
    }

    /// Coral when something has stalled, orange when agents are only waiting.
    static func attentionColor(workspaces: [WorkspaceSession]) -> Color {
        let hasStalled = workspaces.contains { workspace in
            workspace.orchestrator.status.isStalled || workspace.workers.contains { $0.status.isStalled }
        }
        return hasStalled ? SurgeColors.alert : SurgeColors.caution
    }

    /// The placeholder is the only surface that has no text to carry contrast, so it steps its
    /// own fill up instead of relying on a label.
    static func skeletonFill(_ contrast: ColorSchemeContrast) -> Color {
        SurgeInk.primary().opacity(
            contrast == .increased ? skeletonOpacityIncreasedContrast : skeletonOpacity
        )
    }

    static func contrast(_ appearance: SurgeAppearance?, system: ColorSchemeContrast) -> ColorSchemeContrast {
        appearance?.contrast ?? system
    }
}

extension AgentStatus {
    var isStalled: Bool {
        if case .stalled = self { return true }
        return false
    }
}
