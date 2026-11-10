import Carbon.HIToolbox
import CoreGraphics

/// Synthetic keystrokes, sent by virtual key code (`kVK_ANSI_*`), not by character, so they
/// also work while the Russian (or any other) keyboard layout is active. They need the
/// Accessibility permission.
enum KeySender {
    static func commandV() { command(CGKeyCode(kVK_ANSI_V)) }
    static func commandC() { command(CGKeyCode(kVK_ANSI_C)) }

    private static func command(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
