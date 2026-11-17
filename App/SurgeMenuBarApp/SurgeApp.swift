import AppKit
import SurgeCore
import SurgeStateStore
import SurgeUI
import SwiftUI

@main
struct SurgeApp: App {
    var body: some Scene {
        MenuBarExtra {
            PlaceholderPopover()
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("Surge")
        }
        .menuBarExtraStyle(.window)
    }
}

struct PlaceholderPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No agents running")
                .font(.headline)
            Text("Start Claude Code, or point workers at 127.0.0.1:8899.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit Surge") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}
