import SwiftUI

/// The menu bar item: a template glyph, an attention triangle and count when anything needs the
/// user, and the PRD's short text readout. It never animates; the changing numbers are the signal.
struct MenuBarLabel: View {
    let model: AppModel

    private var readout: MenuBarReadout { model.readout }

    var body: some View {
        Label {
            Text(readout.needsYou ? "\(readout.attentionCount) · \(readout.text)" : readout.text)
                .monospacedDigit()
        } icon: {
            if readout.needsYou {
                Image(systemName: "exclamationmark.triangle.fill")
            } else {
                Image(systemName: "bolt.circle.fill")
            }
        }
        .font(.system(size: 11))
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(readout.accessibilityLabel)
    }
}
