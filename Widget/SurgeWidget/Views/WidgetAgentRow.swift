import SurgeCore
import SurgeUI
import SwiftUI

/// The status half of a row. Stalled and idle agents count up on their own through the system
/// timer, so the label stays honest between timeline reloads (TRD 6.2).
struct WidgetStatusText: View {
    let status: AgentStatus
    let color: Color
    /// The word for a state that has no timer. Rows pass nothing and get the short word; the Small
    /// widget passes the PRD's full label, because it has the room.
    var label: String?

    init(status: AgentStatus, color: Color, label: String? = nil) {
        self.status = status
        self.color = color
        self.label = label
    }

    var body: some View {
        text
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
    }

    @ViewBuilder
    private var text: some View {
        switch status {
        case .stalled(let since):
            HStack(spacing: 3) {
                Text(WidgetStatusWording.short(status))
                Text(since, style: .timer)
            }
        case .idle(let since):
            HStack(spacing: 3) {
                Text(WidgetStatusWording.short(status))
                Text(since, style: .timer)
            }
        default:
            Text(label ?? WidgetStatusWording.short(status))
        }
    }
}

/// One agent or sub-agent on a single row: state symbol, name, Fuse, status. The presentation
/// comes from `SurgeUI` so the state word, the Fuse and the VoiceOver sentence are the same as the
/// popover's; only the one-line layout is the widget's.
struct WidgetAgentRow: View {
    private let presentation: AgentRowPresentation
    private let fuseWidth: CGFloat
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { WidgetStyle.contrast(appearance, system: systemContrast) }

    init(reference: WidgetAgentRef, now: Date, fuseWidth: CGFloat = WidgetStyle.fuseWidth) {
        presentation = AgentRowPresentation(
            agent: reference.agent,
            workspaceName: reference.workspaceName,
            now: now,
            kind: reference.parentModelName.map {
                .subAgent(parentName: AgentRowPresentation.displayName(forModel: $0))
            } ?? .agent
        )
        self.fuseWidth = fuseWidth
    }

    var body: some View {
        HStack(spacing: WidgetStyle.rowSpacing) {
            if presentation.kind.isSubAgent {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(SurgeInk.tertiary(contrastLevel))
                    .frame(width: 10, alignment: .center)
                    .accessibilityHidden(true)
            }
            Image(systemName: presentation.stateSymbol)
                .font(SurgeTypography.sans(11))
                .foregroundStyle(WidgetStyle.statusColor(for: presentation.status, contrast: contrastLevel))
                .frame(width: 12, alignment: .center)
            Text(presentation.modelName)
                .font(WidgetStyle.rowName)
                .foregroundStyle(SurgeInk.primary())
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: WidgetStyle.rowSpacing)
            Fuse(presentation.fuse)
                .frame(width: fuseWidth)
            WidgetStatusText(
                status: presentation.status,
                color: WidgetStyle.statusColor(for: presentation.status, contrast: contrastLevel)
            )
            .font(WidgetStyle.rowValue)
            .frame(width: WidgetStyle.valueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

extension AgentRowKind {
    var isSubAgent: Bool {
        if case .subAgent = self { return true }
        return false
    }
}

/// A one-line "└ 2 more agents" style overflow note under a trimmed tree.
struct WidgetOverflowRow: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { WidgetStyle.contrast(appearance, system: systemContrast) }

    var body: some View {
        Text(text)
            .font(WidgetStyle.meta)
            .foregroundStyle(SurgeInk.tertiary(contrastLevel))
            .lineLimit(1)
    }
}
