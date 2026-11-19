import SurgeCore
import SwiftUI

/// One agent or sub-agent row: state symbol, name and value on the first line, provider, Fuse and
/// context label on the second. The whole row is a single VoiceOver element.
public struct AgentRow: View {
    private let presentation: AgentRowPresentation
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(_ presentation: AgentRowPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            firstLine
            secondLine
        }
        .padding(.leading, indent)
        .padding(.vertical, SurgeSpacing.space1)
        .frame(minHeight: SurgeUIStyle.rowMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let tint = SurgeUIStatusStyle.tint(for: presentation.status) {
                RoundedRectangle(cornerRadius: SurgeRadius.row).fill(tint)
            }
        }
        .overlay(alignment: .leading) {
            connector
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var firstLine: some View {
        HStack(spacing: SurgeSpacing.space1) {
            Image(systemName: presentation.stateSymbol)
                .font(SurgeUIFont.rowMeta)
                .foregroundStyle(SurgeUIStatusStyle.color(for: presentation.status, contrast: contrastLevel))
            Text(presentation.modelName)
                .font(SurgeUIFont.rowName)
                .foregroundStyle(SurgeInk.primary())
                .lineLimit(1)
            Spacer(minLength: SurgeSpacing.space1)
            Text(presentation.trailingText)
                .font(SurgeUIFont.rowValue)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var secondLine: some View {
        HStack(spacing: SurgeSpacing.space2) {
            HStack(spacing: SurgeSpacing.space1) {
                ProviderDot(provider: presentation.provider)
                Text(presentation.provider.name)
                    .font(SurgeUIFont.rowMeta)
                    .foregroundStyle(SurgeInk.secondary(contrastLevel))
                    .lineLimit(1)
            }
            .frame(width: SurgeUIStyle.providerColumnWidth, alignment: .leading)
            Fuse(presentation.fuse)
            Text(presentation.fuse.contextLabel)
                .font(SurgeUIFont.rowMeta)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: SurgeUIStyle.contextLabelWidth, alignment: .leading)
        }
    }

    private var indent: CGFloat {
        switch presentation.kind {
        case .agent: 0
        case .subAgent: SurgeUIStyle.subAgentIndent
        }
    }

    /// The sub-agent connector is a hairline through the indent, dimmed to the secondary text colour.
    @ViewBuilder
    private var connector: some View {
        if case .subAgent = presentation.kind {
            Rectangle()
                .fill(SurgeInk.secondary(contrastLevel))
                .frame(width: SurgeUIStyle.connectionWidth)
                .offset(x: SurgeUIStyle.subAgentIndent / 2)
                .accessibilityHidden(true)
        }
    }
}
