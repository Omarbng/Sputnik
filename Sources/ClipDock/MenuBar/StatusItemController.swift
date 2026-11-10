import AppKit
@preconcurrency import KeyboardShortcuts

/// Owns the menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var isCapturing: () -> Bool
        var canPaste: () -> Bool
        var needsLanguages: () -> Bool
        var openPopup: () -> Void
        var allowCapture: () -> Void
        var allowPasting: () -> Void
        var downloadLanguages: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    /// Full clipboard while capturing, empty clipboard while capture is off.
    func refreshIcon() {
        let image = NSImage(
            systemSymbolName: actions.isCapturing() ? "doc.on.clipboard" : "clipboard",
            accessibilityDescription: "ClipDock"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var needsSeparator = false
        if !actions.isCapturing() {
            menu.addItem(item("Capture Off — Allow Clipboard Access…", #selector(allowCapture)))
            needsSeparator = true
        }
        if !actions.canPaste() {
            let allow = item("Allow Pasting…", #selector(allowPasting))
            allow.subtitle = "Needed to paste with ⌘V for you"
            menu.addItem(allow)
            needsSeparator = true
        }
        if actions.needsLanguages() {
            let download = item("Download Translation Languages…", #selector(downloadLanguages))
            download.subtitle = "English and Russian, for offline translation"
            menu.addItem(download)
            needsSeparator = true
        }
        if needsSeparator { menu.addItem(.separator()) }

        let open = item("Open ClipDock", #selector(openPopup))
        open.setShortcut(for: .openPopup)
        menu.addItem(open)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: Private

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openPopup() { actions.openPopup() }
    @objc private func allowCapture() { actions.allowCapture() }
    @objc private func allowPasting() { actions.allowPasting() }
    @objc private func downloadLanguages() { actions.downloadLanguages() }
}
