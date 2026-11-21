import AppKit
import SwiftUI

/// The menu bar item: a template glyph, the attention triangle when anything needs the user, and
/// the PRD's short text readout. It never animates; the changing numbers are the signal.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        MenuBarItem(readout: model.readout)
    }
}

/// The drawn item, apart from the app behind it, so every state can be rendered on its own.
///
/// The menu bar is the system's chrome, not the product's content: the type is the menu bar's own
/// font, which follows the system text size, and the glyph is drawn in the menu bar's template ink.
struct MenuBarItem: View {
    let readout: MenuBarReadout

    var body: some View {
        Label {
            if let text = readout.text {
                Text(text)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: readout.symbolName)
        }
        .font(Font(NSFont.menuBarFont(ofSize: 0)))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.accessibilityLabel)
        // Nothing in the bar animates, the swap to the attention glyph included: it is an instant
        // swap, so no inherited animation may land on it.
        .transaction { $0.animation = nil }
    }
}
