import AppKit
import SwiftUI

/// Shows the paste-permission card in a small window. It closes itself once access is allowed.
@MainActor
final class PasteAccessWindowController {
    private var window: NSWindow?

    func show(access: NSPasteboard.AccessBehavior) {
        guard access != .alwaysAllow else { return }
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.title = "ClipDock"
            window.isReleasedWhenClosed = false
            self.window = window
        }
        update(access: access)
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Re-renders for a new permission state. Does nothing if the card isn't showing.
    func update(access: NSPasteboard.AccessBehavior) {
        guard let window else { return }
        guard access != .alwaysAllow else {
            close()
            return
        }
        let controller = NSHostingController(rootView: PasteAccessCardView(
            access: access,
            onContinue: { PasteboardAccess.requestListing() },
            onOpenSettings: { PasteboardAccess.openSettings() },
            onDismiss: { [weak self] in self?.close() }
        ))
        controller.sizingOptions = .preferredContentSize
        window.contentViewController = controller
    }

    func close() {
        window?.close()
        window = nil
    }
}
