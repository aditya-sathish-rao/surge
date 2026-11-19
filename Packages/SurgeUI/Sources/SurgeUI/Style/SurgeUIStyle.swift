import SurgeCore
import SwiftUI

/// Sizes and opacities the design system specifies but `SurgeCore` does not expose as tokens.
///
/// Every colour here is built from a `SurgeCore` token. The values that are not in `SurgeCore` come
/// from the design system's layout, Fuse and component sections.
enum SurgeUIStyle {
    static let rowMinHeight: CGFloat = 44
    static let subAgentIndent: CGFloat = 16
    static let providerColumnWidth: CGFloat = 78
    static let connectionWidth: CGFloat = 1
    static let notchWidth: CGFloat = 1.5
    static let notchPositions: [Double] = [
        SurgeThresholds.contextHighRatio,
        SurgeThresholds.contextNearLimitRatio,
    ]

    /// White at 14 percent, the Fuse track from the design system.
    static var fuseTrack: Color { SurgeInk.primary().opacity(0.14) }
    /// The notches are cut in the card colour.
    static var notch: Color { SurgeColors.card }
    /// White at 16 percent behind a row that needs you is the design's status tint.
    static let rowTintOpacity: Double = 0.16

    static let hatchSpacing: CGFloat = 5
    static let hatchLineWidth: CGFloat = 2
    static let hatchWashOpacity: Double = 0.18

    static let fuseAnimationDuration: TimeInterval = 0.3
    static let tabAnimationDuration: TimeInterval = 0.26
    static let tabAnimationBounce: Double = 0.35
    static let tabPadding: CGFloat = 3
    static let tabContentHeight: CGFloat = 22
    /// White at 10 percent: the pill tab track and an unselected chip.
    static let controlFillOpacity: Double = 0.10
    static let contrastOutlineWidth: CGFloat = 1
    static let sectionLabelTracking: CGFloat = 0.1

    static let chipHorizontalPadding: CGFloat = 8

    static let chartBarWidth: CGFloat = 12
    static let chartBarGap: CGFloat = 1.5
    static let chartCornerRadius: CGFloat = 6
    static let chartTodayOpacity: Double = 1
    static let chartPastOpacity: Double = 0.7
    static let chartGridOpacity: Double = 0.15
    static let chartTickOpacity: Double = 0.55
    static let throughputChartHeight: CGFloat = 78
    static let chartPointSize: CGFloat = 24
    static let spendChartHeight: CGFloat = 96
    static let proportionalBarHeight: CGFloat = 12
    static let proportionalBarRadius: CGFloat = 3
    static let tokenColumnWidth: CGFloat = 40
    static let usageNameWidth: CGFloat = 148
    static let contextLabelWidth: CGFloat = 92
    static let percentColumnWidth: CGFloat = 36

    static let providerDotSize: CGFloat = 6
    static let legendDotSize: CGFloat = 7
}

/// Named type roles for the views in this package, built from `SurgeCore`'s typography tokens.
///
/// Views never name a font directly. The roles follow the design system's type scale: Body 13,
/// Callout 12, Subheadline 11, Label 10, and Light readouts at 22 and above.
enum SurgeUIFont {
    static let rowName = SurgeTypography.sans(13, weight: .medium)
    static let rowValue = SurgeTypography.sans(12)
    static let rowMeta = SurgeTypography.meta
    static let sectionLabel = SurgeTypography.label
    static let widgetSectionLabel = SurgeTypography.sans(11, weight: .medium)
    static let tabLabel = SurgeTypography.sans(12)
    static let tabLabelSelected = SurgeTypography.sans(12, weight: .medium)
    static let chipLabel = SurgeTypography.sans(11, weight: .medium)
    static let chartHeadline = SurgeTypography.readoutL
    static let chartHeadlineCompact = SurgeTypography.readoutM
    static let chartCaption = SurgeTypography.meta
    static let chartAxis = SurgeTypography.label
    static let chartAxisWidget = SurgeTypography.widgetMeta
    static let balanceAmount = SurgeTypography.title
    static let balanceName = SurgeTypography.body
    static let balanceQualifier = SurgeTypography.meta
    /// Why a balance is missing is prose, so it takes the sans caption rather than the mono path style.
    static let balanceReason = SurgeTypography.meta
    static let balanceCaption = SurgeTypography.path
    static let emptyPrompt = SurgeTypography.mono(13)
    static let emptyDetail = SurgeTypography.body
}

/// The single place a status hue reaches a view.
enum SurgeUIStatusStyle {
    /// Waiting for you owns orange, stalled owns coral, and a healthy agent is drawn in white.
    static func color(for status: AgentStatus, contrast: ColorSchemeContrast) -> Color {
        switch status {
        case .waitingForYou:
            SurgeColors.caution
        case .stalled:
            SurgeColors.alert
        case .compacting, .done, .noSignal:
            SurgeInk.secondary(contrast)
        case .idle:
            SurgeInk.tertiary(contrast)
        case .working:
            SurgeInk.primary()
        }
    }

    static func tint(for status: AgentStatus) -> Color? {
        switch status {
        case .waitingForYou:
            SurgeColors.caution.opacity(SurgeUIStyle.rowTintOpacity)
        case .stalled:
            SurgeColors.alert.opacity(SurgeUIStyle.rowTintOpacity)
        default:
            nil
        }
    }
}
