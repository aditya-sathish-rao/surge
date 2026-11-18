import SwiftUI

/// The three popover tabs. The active pill is white with card-coloured text.
public enum SurgeTab: String, CaseIterable, Identifiable, Sendable {
    case agents
    case usage
    case spend

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .agents: "Agents"
        case .usage: "Usage"
        case .spend: "Spend"
        }
    }

    /// One-based position, used by the tab group's VoiceOver label.
    public var position: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// "Agents, tab, 1 of 3". VoiceOver appends "selected" from the selected trait.
    public var accessibilityLabel: String {
        "\(title), tab, \(position) of \(Self.allCases.count)"
    }

    public var shortcut: KeyEquivalent {
        switch self {
        case .agents: "1"
        case .usage: "2"
        case .spend: "3"
        }
    }
}
