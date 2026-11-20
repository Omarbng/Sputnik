import AppKit
import ApplicationServices

/// The Accessibility permission, which Sputnik needs to send ⌘V to other apps.
@MainActor
enum AccessibilityAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt (it appears once per app), which also adds Sputnik to the
    /// list in System Settings.
    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// System Settings → Privacy & Security → Accessibility.
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
