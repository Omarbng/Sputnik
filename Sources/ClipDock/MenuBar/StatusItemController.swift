import AppKit
import ClipDockCore

/// Owns the menu-bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let history: HistoryModel
    private let isCapturing: () -> Bool
    private let onAllowAccess: () -> Void

    init(history: HistoryModel, isCapturing: @escaping () -> Bool, onAllowAccess: @escaping () -> Void) {
        self.history = history
        self.isCapturing = isCapturing
        self.onAllowAccess = onAllowAccess
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    /// Full clipboard while capturing, empty clipboard while capture is off.
    func refreshIcon() {
        let image = NSImage(
            systemSymbolName: isCapturing() ? "doc.on.clipboard" : "clipboard",
            accessibilityDescription: "ClipDock"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !isCapturing() {
            let allow = NSMenuItem(
                title: "Capture Off — Allow Clipboard Access…", action: #selector(allowAccess), keyEquivalent: ""
            )
            allow.target = self
            menu.addItem(allow)
            menu.addItem(.separator())
        }

        // Temporary (M1): the last 5 captures, to check capture. The popup replaces this in M2.
        menu.addItem(.sectionHeader(title: "Recent"))
        let recent = history.items.prefix(5)
        if recent.isEmpty {
            menu.addItem(NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: ""))
        }
        for item in recent {
            menu.addItem(recentMenuItem(for: item))
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: Private

    private func recentMenuItem(for item: ClipItem) -> NSMenuItem {
        let title = item.title
        let shortTitle = title.count > 60 ? title.prefix(60) + "…" : title
        let menuItem = NSMenuItem(title: shortTitle.isEmpty ? "(blank)" : String(shortTitle), action: #selector(noop), keyEquivalent: "")
        menuItem.target = self
        menuItem.image = NSImage(systemSymbolName: Self.glyph(for: item.kind), accessibilityDescription: item.kind.rawValue)
        menuItem.subtitle = [item.sourceAppName, RelativeTime.short(item.lastUsedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return menuItem
    }

    private static func glyph(for kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }

    @objc private func allowAccess() {
        onAllowAccess()
    }

    @objc private func noop() {}
}
