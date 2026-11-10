import AppKit

/// Owns the menu-bar icon and its menu.
@MainActor
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipDock")
            image?.isTemplate = true
            button.image = image
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit ClipDock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }
}
