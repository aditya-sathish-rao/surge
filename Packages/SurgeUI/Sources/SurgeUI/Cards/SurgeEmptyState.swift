import SurgeCore
import SwiftUI

/// The popover's empty state: the prompt in mono, then the next step, always on screen.
public struct SurgeEmptyState: View {
    public static let prompt = "> no agents running_"
    public static let title = "No agents running"
    public static let detail = "Start Claude Code, or point workers at 127.0.0.1:8899."
    public static let accessibilityLabel = "No agents running. Start Claude Code, or point workers at 127.0.0.1:8899."

    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
            Text(Self.prompt)
                .font(SurgeUIFont.emptyPrompt)
                .foregroundStyle(SurgeInk.primary())
            Text(Self.detail)
                .font(SurgeUIFont.emptyDetail)
                .foregroundStyle(SurgeInk.secondary(contrastLevel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel)
    }
}
