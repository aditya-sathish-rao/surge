import Foundation
import SurgeCore

/// The six states the Fuse can draw. Status owns the tripped state; the rest describe fill level.
public enum FuseState: String, Sendable, Equatable, CaseIterable {
    case normal
    case high
    case nearLimit
    case tripped
    case idle
    case unknown
}

/// How the hatch leaves the Fuse when the agent recovers. Every case plays once.
public enum FuseHatchClear: Sendable, Equatable {
    /// The hatch wipes away from the left edge over a spring, revealing the fill behind it.
    case leftToRight
    /// Reduce Motion: the hatch dissolves in place and the fill fades in under it.
    case crossFade
}

/// Everything a Fuse draws and says, derived once from an agent so the view holds no rules.
public struct FusePresentation: Sendable, Equatable {
    public static let noDataLabel = "No data"
    public static let noDataVoiceOver = "Context unavailable, no data"

    public let state: FuseState
    /// The threshold the fill crossed, or nil when there is no data. Status never changes it.
    public let level: ContextLevel?
    /// The fill, or nil when there is no data to draw. The axis is always 0 to 100 percent.
    public let fillRatio: Double?
    /// The visible label that always sits beside the Fuse.
    public let label: String
    /// The percentage label a row shows. The row already carries the state word, so a tripped or
    /// idle Fuse in a row reads its context percentage here instead of repeating the status.
    public let contextLabel: String
    /// The context part of the row's VoiceOver sentence, without the trailing full stop.
    public let contextClause: String
    /// The Fuse read on its own, including the model's window.
    public let accessibilityLabel: String

    public var isTripped: Bool { state == .tripped }

    /// A stalled agent's context is not growing, so the fill holds still and the hatch is what
    /// moves. Every other state lets the fill ease to its new value.
    public var fillAnimates: Bool { !isTripped }

    public init(
        state: FuseState,
        level: ContextLevel?,
        fillRatio: Double?,
        label: String,
        contextLabel: String,
        contextClause: String,
        accessibilityLabel: String
    ) {
        self.state = state
        self.level = level
        self.fillRatio = fillRatio
        self.label = label
        self.contextLabel = contextLabel
        self.contextClause = contextClause
        self.accessibilityLabel = accessibilityLabel
    }

    public init(agent: AgentNode, now: Date) {
        guard agent.status != .noSignal, agent.maxContextWindow > 0 else {
            self.init(
                state: .unknown,
                level: nil,
                fillRatio: nil,
                label: Self.noDataLabel,
                contextLabel: Self.noDataLabel,
                contextClause: "Context unavailable",
                accessibilityLabel: Self.noDataVoiceOver
            )
            return
        }

        let ratio = agent.contextUsageRatio
        let level = SurgeThresholds.contextLevel(forRatio: ratio)
        let percentNumber = Int((ratio * 100).rounded())
        let percent = "\(percentNumber)%"
        let state = Self.state(for: agent.status, level: level)
        let modifierTitle = Self.modifierTitle(for: level)

        self.init(
            state: state,
            level: level,
            fillRatio: ratio,
            label: Self.visibleLabel(
                state: state,
                percent: percent,
                modifierTitle: modifierTitle,
                status: agent.status,
                now: now
            ),
            contextLabel: modifierTitle.map { "\(percent) · \($0)" } ?? percent,
            contextClause: Self.contextClause(percentNumber: percentNumber, modifier: Self.modifierWord(for: level)),
            accessibilityLabel: Self.accessibilityLabel(
                percentNumber: percentNumber,
                window: Self.spelledTokenWindow(agent.maxContextWindow),
                modifier: Self.modifierWord(for: level)
            )
        )
    }

    public static func state(for status: AgentStatus, level: ContextLevel) -> FuseState {
        switch status {
        case .stalled:
            return .tripped
        case .idle:
            return .idle
        default:
            return state(for: level)
        }
    }

    public static func state(for level: ContextLevel) -> FuseState {
        switch level {
        case .normal: .normal
        case .high: .high
        case .nearLimit: .nearLimit
        }
    }

    /// The hatch clears left to right on recovery. Reduce Motion substitutes a cross-fade, so the
    /// preference changes the picture here rather than in the view.
    public static func hatchClear(reduceMotion: Bool) -> FuseHatchClear {
        reduceMotion ? .crossFade : .leftToRight
    }

    /// "42%", "78% · High", "12% · Idle 4m", or the stall word when the Fuse is tripped.
    public static func visibleLabel(
        state: FuseState,
        percent: String,
        modifierTitle: String?,
        status: AgentStatus,
        now: Date
    ) -> String {
        switch state {
        case .tripped:
            return SurgeFormatting.statusLabel(status, now: now)
        case .idle:
            return "\(percent) · \(modifierTitle ?? SurgeFormatting.statusLabel(status, now: now))"
        case .normal, .unknown:
            return percent
        case .high, .nearLimit:
            return modifierTitle.map { "\(percent) · \($0)" } ?? percent
        }
    }

    public static func contextClause(percentNumber: Int, modifier: String?) -> String {
        modifier.map { "Context \(percentNumber) percent, \($0)" } ?? "Context \(percentNumber) percent"
    }

    public static func accessibilityLabel(percentNumber: Int, window: String, modifier: String?) -> String {
        modifier.map { "Context \(percentNumber) percent of \(window) tokens, \($0)" }
            ?? "Context \(percentNumber) percent of \(window) tokens"
    }

    static func modifierWord(for level: ContextLevel) -> String? {
        switch level {
        case .normal: nil
        case .high: "high"
        case .nearLimit: "near limit"
        }
    }

    static func modifierTitle(for level: ContextLevel) -> String? {
        switch level {
        case .normal: nil
        case .high: "High"
        case .nearLimit: "Near limit"
        }
    }

    /// Reads a context window the way VoiceOver should say it: "200 thousand", "1.5 million".
    public static func spelledTokenWindow(_ tokens: Int) -> String {
        guard tokens > 0 else { return "0" }
        if tokens >= 1_000_000 {
            return "\(compact(Double(tokens) / 1_000_000)) million"
        }
        if tokens >= 1_000 {
            return "\(compact(Double(tokens) / 1_000)) thousand"
        }
        return "\(tokens)"
    }

    private static func compact(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}
