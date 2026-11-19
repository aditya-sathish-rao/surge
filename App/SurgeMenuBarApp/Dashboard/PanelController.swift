import AppKit
import SurgeCore
import SurgeUI
import SwiftUI

/// The detached, floating panel titled "Surge" that the popover detaches into.
///
/// It hosts the same dashboard the popover shows, so the two surfaces never drift apart.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSPanel?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show(filter: WorkspaceFilter) {
        let panel = window ?? makePanel()
        window = panel
        let content = NSHostingView(
            rootView: DashboardView(model: model, isPanel: true, initialFilter: filter)
        )
        panel.contentView = content
        let fitting = content.fittingSize
        panel.setContentSize(
            NSSize(
                width: SurgeSize.popoverWidth,
                height: min(max(fitting.height, 320), SurgeSize.popoverMaxHeight)
            )
        )
        if !panel.isVisible {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func toggle(filter: WorkspaceFilter) {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        show(filter: filter)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: SurgeSize.popoverWidth, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Surge"
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
