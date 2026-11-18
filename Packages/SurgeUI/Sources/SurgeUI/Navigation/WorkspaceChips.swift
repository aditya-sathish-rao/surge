import SurgeCore
import SwiftUI

/// Which workspaces the agent list shows. Chips only filter what is visible.
public enum WorkspaceFilter: Hashable, Sendable, Identifiable {
    case all
    case workspace(UUID)

    public var id: String {
        switch self {
        case .all: "all"
        case .workspace(let id): id.uuidString
        }
    }
}

/// One workspace chip and the count it carries.
public struct WorkspaceChip: Identifiable, Sendable, Equatable {
    public let filter: WorkspaceFilter
    public let title: String
    public let agentCount: Int

    public var id: String { filter.id }

    public var countText: String {
        agentCount == 1 ? "1 agent" : "\(agentCount) agents"
    }

    public var titleWithCount: String {
        "\(title) \(agentCount)"
    }

    /// The count is part of the accessible name: "surge-widget, 3 agents".
    public var accessibilityLabel: String {
        "\(title), \(countText)"
    }

    /// "All" first, then one chip per workspace in the order the store supplies them.
    /// A workspace counts its orchestrator and every sub-agent.
    public static func make(for workspaces: [WorkspaceSession]) -> [WorkspaceChip] {
        let all = WorkspaceChip(
            filter: .all,
            title: "All",
            agentCount: workspaces.reduce(0) { $0 + 1 + $1.workers.count }
        )
        let chips = workspaces.map { workspace in
            WorkspaceChip(
                filter: .workspace(workspace.id),
                title: workspace.name,
                agentCount: 1 + workspace.workers.count
            )
        }
        return [all] + chips
    }
}

/// The filter row above the agent tree. Selecting "All" clears the others, since one chip is selected.
public struct WorkspaceChips: View {
    private let chips: [WorkspaceChip]
    @Binding private var selection: WorkspaceFilter
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(workspaces: [WorkspaceSession], selection: Binding<WorkspaceFilter>) {
        chips = WorkspaceChip.make(for: workspaces)
        _selection = selection
    }

    public var body: some View {
        WrapHStackLayout(spacing: SurgeSpacing.space1, lineSpacing: SurgeSpacing.space1) {
            ForEach(chips) { chip in
                chipButton(chip)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace filter")
    }

    private func chipButton(_ chip: WorkspaceChip) -> some View {
        let isSelected = chip.filter == selection
        return Button {
            selection = chip.filter
        } label: {
            HStack(spacing: SurgeSpacing.space1) {
                Text(chip.title)
                    .foregroundStyle(isSelected ? SurgeColors.card : SurgeInk.secondary(contrastLevel))
                Text("\(chip.agentCount)")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? SurgeColors.card : SurgeInk.tertiary(contrastLevel))
            }
            .font(SurgeUIFont.chipLabel)
            .lineLimit(1)
            .padding(.horizontal, SurgeUIStyle.chipHorizontalPadding)
            .frame(height: SurgeSize.chipHeight)
            .background(
                isSelected ? SurgeInk.primary() : SurgeInk.primary().opacity(SurgeUIStyle.controlFillOpacity),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
