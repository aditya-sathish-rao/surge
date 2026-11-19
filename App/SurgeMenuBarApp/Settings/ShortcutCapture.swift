import AppKit
import Observation

/// Watches the next key press so Settings can record a global shortcut.
@MainActor
@Observable
final class ShortcutCapture {
    private(set) var isRecording = false
    private(set) var captured: GlobalShortcut?
    private var monitor: Any?

    func start() {
        guard !isRecording else { return }
        captured = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(GlobalShortcut.relevantModifiers)
            let characters = event.charactersIgnoringModifiers
            MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, modifiers: modifiers, characters: characters)
            }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }

    func reset() {
        captured = nil
    }

    private func handle(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String?
    ) {
        if keyCode == 53 {
            stop()
            return
        }
        guard !modifiers.isEmpty, let characters, !characters.isEmpty else { return }
        captured = GlobalShortcut(keyCode: keyCode, modifiers: modifiers.rawValue, key: characters.uppercased())
        stop()
    }
}
