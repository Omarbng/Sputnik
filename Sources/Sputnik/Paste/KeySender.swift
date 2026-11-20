import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Synthetic keystrokes, sent by virtual key code (`kVK_ANSI_*`), not by character, so they
/// also work while the Russian (or any other) keyboard layout is active. They need the
/// Accessibility permission.
enum KeySender {
    static func commandV() { command(CGKeyCode(kVK_ANSI_V)) }
    static func commandC() { command(CGKeyCode(kVK_ANSI_C)) }

    /// Keys Omar may still be holding when a dictation or shortcut finishes (fn + ⌃ for a
    /// command, fn + ⇧ for a translation). A ⌘C or ⌘V sent meanwhile reaches the app with them
    /// added: ⇧⌘V opens Cursor's Markdown preview instead of pasting, ⌃⌘C copies nothing.
    private static let heldModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]

    /// Waits until those keys are up (at most `timeout`). Returns false if they're still held.
    @discardableResult
    static func waitForModifierRelease(timeout: Duration = .milliseconds(1_500)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !CGEventSource.flagsState(.hidSystemState).intersection(heldModifiers).isEmpty {
            guard ContinuousClock.now < deadline else {
                Log.paste.notice("modifiers still held; sending anyway")
                return false
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
        return true
    }

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
