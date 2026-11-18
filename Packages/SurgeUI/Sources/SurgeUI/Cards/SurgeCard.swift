import SurgeCore
import SwiftUI

/// The opaque dark card every surface puts its content in. The rim around it is the system's.
public struct SurgeCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(SurgeSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SurgeColors.card, in: RoundedRectangle(cornerRadius: SurgeRadius.card))
    }
}

/// A small uppercase section header. Uppercase is reserved for section labels.
public struct SurgeSectionLabel: View {
    private let text: String
    private let isWidget: Bool
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(_ text: String, isWidget: Bool = false) {
        self.text = text
        self.isWidget = isWidget
    }

    public var body: some View {
        Text(text.uppercased())
            .font(isWidget ? SurgeUIFont.widgetSectionLabel : SurgeUIFont.sectionLabel)
            .tracking(SurgeUIStyle.sectionLabelTracking)
            .foregroundStyle(SurgeInk.tertiary(contrastLevel))
            .accessibilityAddTraits(.isHeader)
    }
}
