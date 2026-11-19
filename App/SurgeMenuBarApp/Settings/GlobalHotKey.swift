import AppKit
import Carbon.HIToolbox

/// Registers the user's global shortcut with Carbon's hot key API, which needs no Accessibility
/// permission. An unset shortcut unregisters the previous one and registers nothing.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    private init() {}

    func register(_ shortcut: GlobalShortcut?, action: @escaping @MainActor () -> Void) {
        unregister()
        guard let shortcut else { return }
        self.action = action
        installHandler()
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: surgeHotKeySignature, id: surgeHotKeyIdentifier)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(shortcut.modifierFlags),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            hotKeyRef = reference
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        action = nil
    }

    fileprivate func fire() {
        action?()
    }

    private func installHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), surgeHotKeyHandler, 1, &eventType, nil, &eventHandler)
    }
}

private let surgeHotKeySignature: OSType = 0x5355_5247  // 'SURG'
private let surgeHotKeyIdentifier: UInt32 = 1

private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    return modifiers
}

private func surgeHotKeyHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr, identifier.signature == surgeHotKeySignature,
        identifier.id == surgeHotKeyIdentifier
    else {
        return OSStatus(eventNotHandledErr)
    }
    Task { @MainActor in
        GlobalHotKey.shared.fire()
    }
    return noErr
}
