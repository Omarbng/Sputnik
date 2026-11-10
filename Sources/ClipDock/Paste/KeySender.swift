import Carbon.HIToolbox
import CoreGraphics

enum KeySender {
    /// Sends ⌘V by virtual key code (`kVK_ANSI_V`), not by character, so it also works while
    /// the Russian (or any other) keyboard layout is active. Needs Accessibility permission.
    static func commandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
