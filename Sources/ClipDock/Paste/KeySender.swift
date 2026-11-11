import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Synthetic keystrokes, sent by virtual key code (`kVK_ANSI_*`), not by character, so they
/// also work while the Russian (or any other) keyboard layout is active. They need the
/// Accessibility permission.
enum KeySender {
    static func commandV() { command(CGKeyCode(kVK_ANSI_V)) }
    static func commandC() { command(CGKeyCode(kVK_ANSI_C)) }

    private static func command(_ key: CGKeyCode) {
        #if CLIPDOCK_TEST_BUILD
        // Test builds launched for scripts send keys only into the test target, checked right
        // before sending, so a test can't paste into an app Omar is using at that moment.
        if ProcessInfo.processInfo.environment["CLIPDOCK_TEST_TARGET_ONLY"] == "1",
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.omar.clipdock.testtarget" {
            Log.paste.notice("test build: key not sent, the test target isn't frontmost")
            return
        }
        #endif
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
