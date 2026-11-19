import AppKit
import Foundation

/// One global keyboard shortcut the user recorded. There is no default: an unset value means
/// Surge has no global shortcut, as the PRD requires.
struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt
    let key: String

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantModifiers)
    }

    /// "⌃⌥⇧⌘K", the way the keyboard settings show it.
    var displayName: String {
        var text = ""
        let flags = modifierFlags
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }
}
