import SurgeCore
import SwiftUI

/// Pill tabs over a standard tab group: arrow keys and Command-1 to Command-3 move the selection,
/// and the white pill slides unless Reduce Motion is on.
public struct PillTabs: View {
    @Binding private var selection: SurgeTab
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.surgeAppearance) private var appearance

    private var reduceMotion: Bool { SurgeAccessibility.reduceMotion(appearance, system: systemReduceMotion) }
    private var contrastLevel: ColorSchemeContrast { SurgeAccessibility.contrast(appearance, system: systemContrast) }

    public init(selection: Binding<SurgeTab>) {
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(SurgeTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(SurgeUIStyle.tabPadding)
        .background(SurgeInk.primary().opacity(SurgeUIStyle.controlFillOpacity), in: Capsule())
        .frame(height: SurgeSize.pillTabHeight)
        .animation(
            reduceMotion
                ? nil
                : .spring(duration: SurgeUIStyle.tabAnimationDuration, bounce: SurgeUIStyle.tabAnimationBounce),
            value: selection
        )
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: select(offset: -1)
            case .right: select(offset: 1)
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    private func tabButton(_ tab: SurgeTab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(tab.title)
                .font(selection == tab ? SurgeUIFont.tabLabelSelected : SurgeUIFont.tabLabel)
                .foregroundStyle(
                    selection == tab ? SurgeColors.card : SurgeInk.secondary(contrastLevel)
                )
                .frame(maxWidth: .infinity, minHeight: SurgeUIStyle.tabContentHeight)
                .background {
                    if selection == tab {
                        Capsule()
                            .fill(SurgeInk.primary())
                            .matchedGeometryEffect(id: "pill", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.shortcut, modifiers: .command)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }

    private func select(offset: Int) {
        let tabs = SurgeTab.allCases
        guard let index = tabs.firstIndex(of: selection) else { return }
        let next = (index + offset + tabs.count) % tabs.count
        selection = tabs[next]
    }
}
