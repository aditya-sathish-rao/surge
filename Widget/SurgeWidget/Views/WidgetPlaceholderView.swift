import SurgeCore
import SurgeUI
import SwiftUI

/// The placeholder before first data: grey capsules for meters and grey bars for text.
struct WidgetPlaceholderView: View {
    let layout: WidgetLayout
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var fill: Color {
        WidgetStyle.skeletonFill(WidgetStyle.contrast(appearance, system: systemContrast))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
            WidgetPlaceholderBar(width: 54, height: 9, fill: fill)
            switch layout {
            case .small:
                Spacer(minLength: 0)
                WidgetPlaceholderBar(width: 120, height: 13, fill: fill)
                WidgetPlaceholderBar(width: 88, height: 9, fill: fill)
                HStack(spacing: SurgeSpacing.space2) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(fill).frame(width: WidgetStyle.miniFuseWidth, height: 30)
                    }
                }
            case .medium:
                rows(count: 4)
                Spacer(minLength: 0)
                WidgetPlaceholderBar(width: 150, height: 9, fill: fill)
            case .large:
                rows(count: 5)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: SurgeRadius.tile)
                    .fill(fill)
                    .frame(height: 60)
                WidgetPlaceholderBar(width: 150, height: 9, fill: fill)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Surge is loading")
    }

    private func rows(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: WidgetStyle.rowSpacing) {
                    Circle().fill(fill).frame(width: 10, height: 10)
                    WidgetPlaceholderBar(width: index.isMultiple(of: 2) ? 86 : 64, height: 8, fill: fill)
                    Spacer(minLength: 0)
                    Capsule().fill(fill).frame(width: WidgetStyle.fuseWidth, height: 6)
                    WidgetPlaceholderBar(width: 46, height: 8, fill: fill)
                }
            }
        }
    }
}

private struct WidgetPlaceholderBar: View {
    let width: CGFloat
    let height: CGFloat
    let fill: Color

    var body: some View {
        Capsule()
            .fill(fill)
            .frame(width: width, height: height)
    }
}
