import AppKit
import SurgeCore
import SurgeUI
import SwiftUI

/// The popover and the detached panel share this view: the header, the three tabs and their cards.
struct DashboardView: View {
    private let model: AppModel
    private let isPanel: Bool

    @State private var tab: SurgeTab = .agents
    @State private var filter: WorkspaceFilter
    @State private var expandedAgentID: String?
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.openSettings) private var openSettings

    init(model: AppModel, isPanel: Bool = false, initialFilter: WorkspaceFilter = .all) {
        self.model = model
        self.isPanel = isPanel
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        VStack(spacing: SurgeSpacing.cardGap) {
            header
            ScrollView {
                tabContent
                    .padding(.top, SurgeSpacing.cardGap)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .frame(height: min(max(contentHeight, 1), 560))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        }
        .padding(SurgeSpacing.section)
        .frame(width: SurgeSize.popoverWidth)
        .animation(systemReduceMotion ? nil : .easeInOut(duration: 0.2), value: tab)
        .onAppear { model.surfaceOpened() }
    }

    private var header: some View {
        SurgeCard {
            VStack(alignment: .leading, spacing: SurgeSpacing.space2) {
                HStack(alignment: .top, spacing: SurgeSpacing.space2) {
                    spendReadout
                    Spacer(minLength: SurgeSpacing.space2)
                    controls
                }
                PillTabs(selection: $tab)
            }
        }
    }

    private var spendReadout: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.space1) {
            SurgeSectionLabel("Spent today")
            Text(SurgeFormatting.cost(model.todaySpendUSD))
                .font(SurgeTypography.readoutL)
                .foregroundStyle(SurgeInk.primary())
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("\(MenuBarReadout.spokenUSD(model.todaySpendUSD)) spent today")
        }
        .contentShape(Rectangle())
        .gesture(detachGesture)
    }

    private var detachGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard !isPanel else { return }
                let movedFar = abs(value.translation.height) > 36 || abs(value.translation.width) > 60
                guard movedFar else { return }
                model.detach(filter: filter)
            }
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: SurgeSpacing.space1) {
            statusLine
            HStack(spacing: SurgeSpacing.space1) {
                if !isPanel {
                    iconButton("macwindow.on.rectangle", label: "Open in a panel") {
                        model.detach(filter: filter)
                    }
                }
                moreMenu
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.isPaused {
            Text("Monitoring paused")
                .font(SurgeTypography.meta)
                .foregroundStyle(SurgeInk.secondary(systemContrast))
        } else if model.storeModel.attentionCount > 0 {
            HStack(spacing: SurgeSpacing.space1) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(SurgeTypography.label)
                Text("\(model.storeModel.attentionCount) need you")
                    .font(SurgeTypography.meta)
                    .monospacedDigit()
            }
            .foregroundStyle(SurgeColors.caution)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.storeModel.attentionCount) agents need you")
        } else {
            Text("All agents working")
                .font(SurgeTypography.meta)
                .foregroundStyle(SurgeInk.secondary(systemContrast))
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(model.isPaused ? "Resume Monitoring" : "Pause Monitoring") {
                Task { await model.togglePause() }
            }
            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit Surge") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis")
                .font(SurgeTypography.body)
                .foregroundStyle(SurgeInk.secondary(systemContrast))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(SurgeTypography.body)
                .foregroundStyle(SurgeInk.secondary(systemContrast))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .agents:
            AgentsTab(
                model: model,
                filter: $filter,
                expandedAgentID: $expandedAgentID
            )
        case .usage:
            UsageTab(model: model)
        case .spend:
            SpendTab(model: model)
        }
    }
}

/// Measures the tab content so the popover grows with it and scrolls only past the maximum.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
