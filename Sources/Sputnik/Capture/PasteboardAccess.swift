import AppKit

/// The macOS 15.4+ "Paste from Other Apps" permission. Reading `accessBehavior` never prompts.
@MainActor
enum PasteboardAccess {
    static var behavior: NSPasteboard.AccessBehavior { NSPasteboard.general.accessBehavior }

    /// System Settings → Privacy & Security → Paste from Other Apps.
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// In the `.default` state Sputnik isn't listed in System Settings yet. One deliberate read
    /// makes macOS show its prompt and list the app. The data is discarded unseen.
    static func requestListing() {
        let pasteboard = NSPasteboard.general
        if let type = pasteboard.types?.first {
            _ = pasteboard.data(forType: type)
        }
    }
}

extension NSPasteboard.AccessBehavior {
    var logName: String {
        switch self {
        case .default: "default"
        case .ask: "ask"
        case .alwaysAllow: "alwaysAllow"
        case .alwaysDeny: "alwaysDeny"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}
