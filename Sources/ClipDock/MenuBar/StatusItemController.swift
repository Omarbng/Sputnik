import AppKit
@preconcurrency import KeyboardShortcuts

/// Owns the menu-bar icon and its menu: Open ClipDock, Pause capture, Clear history…,
/// Shortcuts…, Settings…, Quit, plus setup items while something still needs a permission or download.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var hasClipboardAccess: () -> Bool
        var pausedUntil: () -> Date?
        var canPaste: () -> Bool
        var needsLanguages: () -> Bool
        var openPopup: () -> Void
        var pause: (_ seconds: TimeInterval?) -> Void
        var resume: () -> Void
        var clearHistory: () -> Void
        var openSettings: () -> Void
        var allowCapture: () -> Void
        var allowPasting: () -> Void
        var downloadLanguages: () -> Void
        /// "2 of 3" while a paste stack is waiting for ⌘V, else nil.
        var pasteStackProgress: () -> String?
        var stopPasteStack: () -> Void
        var openGuide: () -> Void
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

    /// Full clipboard while capturing; empty clipboard while paused or without access.
    func refreshIcon() {
        let capturing = actions.hasClipboardAccess() && actions.pausedUntil() == nil
        let image = NSImage(
            systemSymbolName: capturing ? "doc.on.clipboard" : "clipboard",
            accessibilityDescription: capturing ? "Sputnik" : "Sputnik (capture paused)"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addSetupItems(to: menu)
        if let progress = actions.pasteStackProgress() {
            let stop = item("Stop Paste Stack", #selector(stopPasteStack))
            stop.subtitle = "\(progress) on the clipboard — each ⌘V pastes the next"
            menu.addItem(stop)
            menu.addItem(.separator())
        }

        let open = item("Open Sputnik", #selector(openPopup))
        open.setShortcut(for: .openPopup)
        if let tap = AppSettings.popupTap {
            open.subtitle = "Tap \(tap.symbol) \(tap.name) twice"
        }
        menu.addItem(open)
        menu.addItem(pauseItem())
        menu.addItem(item("Clear History…", #selector(clearHistory)))
        menu.addItem(.separator())

        let guide = item("Shortcuts…", #selector(openGuide))
        guide.subtitle = "Every key and voice command"
        menu.addItem(guide)
        let settings = item("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(withTitle: "Quit Sputnik", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: Private

    private func addSetupItems(to menu: NSMenu) {
        var added = false
        if !actions.hasClipboardAccess() {
            menu.addItem(item("Capture Off — Allow Clipboard Access…", #selector(allowCapture)))
            added = true
        }
        if !actions.canPaste() {
            let allow = item("Allow Pasting…", #selector(allowPasting))
            allow.subtitle = "Needed to paste with ⌘V for you"
            menu.addItem(allow)
            added = true
        }
        if actions.needsLanguages() {
            let download = item("Download Translation Languages…", #selector(downloadLanguages))
            download.subtitle = "English, Russian and French, for offline translation"
            menu.addItem(download)
            added = true
        }
        if added { menu.addItem(.separator()) }
    }

    /// "Pause Capture ▸" while capturing, "Resume Capture" while paused.
    private func pauseItem() -> NSMenuItem {
        if let until = actions.pausedUntil() {
            let resume = item("Resume Capture", #selector(resume))
            resume.subtitle = until == .distantFuture
                ? "Paused until you resume"
                : "Paused until \(until.formatted(date: .omitted, time: .shortened))"
            return resume
        }
        let pause = NSMenuItem(title: "Pause Capture", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, seconds) in [("For 15 Minutes", 15.0 * 60), ("For 1 Hour", 60.0 * 60), ("Until Resumed", -1)] {
            let option = item(title, #selector(pauseChosen(_:)))
            option.representedObject = seconds
            submenu.addItem(option)
        }
        pause.submenu = submenu
        return pause
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pauseChosen(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        actions.pause(seconds < 0 ? nil : seconds)
    }

    @objc private func openPopup() { actions.openPopup() }
    @objc private func resume() { actions.resume() }
    @objc private func clearHistory() { actions.clearHistory() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func allowCapture() { actions.allowCapture() }
    @objc private func allowPasting() { actions.allowPasting() }
    @objc private func downloadLanguages() { actions.downloadLanguages() }
    @objc private func stopPasteStack() { actions.stopPasteStack() }
    @objc private func openGuide() { actions.openGuide() }
}
