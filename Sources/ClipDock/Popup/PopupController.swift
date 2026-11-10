import AppKit
import ClipDockCore
import SwiftUI

/// Owns the popup. The panel is created once at launch and then only shown and hidden, so
/// opening is instant. It closes on Esc, a click outside, picking an item, or losing focus.
@MainActor
final class PopupController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    let model: PopupViewModel
    private let panel = PopupPanel()
    private let searchField = NSTextField.popupSearchField()
    private let actions: ItemActions
    private let translation: TranslationService
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    /// ⌘, in the popup.
    var onOpenSettings: (() -> Void)?

    var isVisible: Bool { panel.isVisible }
    /// For debug snapshots.
    var contentView: NSView? { panel.contentView }
    /// The visible dock and card (the panel itself is larger, for tooltips and shadows).
    var frame: CGRect { PopupLayout.contentFrame(inWindow: panel.frame) }

    /// True when the dock and card sit entirely inside one screen's visible frame.
    var isFullyOnScreen: Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
    }

    init(
        history: HistoryModel, icons: AppIconCache, thumbnails: ThumbnailCache,
        actions: ItemActions, translation: TranslationService
    ) {
        let model = PopupViewModel(history: history)
        self.model = model
        self.actions = actions
        self.translation = translation
        super.init()

        let root = PopupRootView(
            model: model, icons: icons, thumbnails: thumbnails, searchField: searchField,
            onDock: { [weak self] item in self?.handleDock(item) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []  // fixed-size panel: SwiftUI must not resize the window
        model.onPick = { [weak self] item in self?.paste(item) }
        panel.contentView = hosting
        panel.setContentSize(PopupLayout.windowSize)
        panel.acceptsMouseMovedEvents = true  // dock hover and tooltips
        panel.hasShadow = false  // the SwiftUI surfaces draw their own shadows
        panel.delegate = self
        searchField.delegate = self
    }

    enum CloseReason: String {
        case toggle, escape, picked, resignedKey, clickOutside, other
    }

    func toggle() {
        isVisible ? close(.toggle) : show()
    }

    /// Renders the panel once at launch, fully transparent and without taking focus, so the
    /// first real open is as fast as later ones. The first SwiftUI render costs ~150 ms.
    func prewarm() {
        model.prepareForOpen()
        panel.alphaValue = 0
        panel.setFrame(CGRect(origin: NSEvent.mouseLocation, size: PopupLayout.windowSize), display: false)
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    func show() {
        let timing = OpenTiming()
        let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        model.prepareForOpen()
        searchField.stringValue = ""

        // The dock and card go at the cursor; the panel extends around them.
        let screens = NSScreen.screens.map { PopupPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let content = PopupPlacement.frame(size: PopupLayout.contentSize, cursor: NSEvent.mouseLocation, screens: screens)
        panel.setFrame(PopupLayout.windowFrame(forContent: content), display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        installMonitors()
        panel.displayIfNeeded()
        timing.finish()
        let frontAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        Log.popup.notice("shown key=\(self.panel.isKeyWindow, privacy: .public) appActive=\(NSApp.isActive, privacy: .public) front=\(frontBefore, privacy: .public)->\(frontAfter, privacy: .public)")
    }

    func close(_ reason: CloseReason = .other) {
        removeMonitors()
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        Log.popup.notice("closed reason=\(reason.rawValue, privacy: .public)")
    }

    func perform(_ command: PopupCommand) {
        switch command {
        case .close:
            close(.escape)
        case .moveUp:
            model.moveSelection(by: -1)
        case .moveDown:
            model.moveSelection(by: 1)
        case .pasteSelected:
            if let text = model.selectedTranslation {
                actions.pasteTranslation(text, closePopup: { close(.picked) })
            } else if let item = model.selectedItem {
                paste(item)
            }
        case .pasteNumber(let number):
            if let item = model.item(at: number - 1) { paste(item) }
        case .copySelected:
            if let text = model.selectedTranslation {
                actions.copyTranslation(text, closePopup: { close(.picked) })
            } else if let item = model.selectedItem {
                actions.copy(item, closePopup: { close(.picked) })
            }
        case .translateSelected:
            translateSelected()
        case .toggleMark:
            if let id = model.selectedItem?.id { model.marks.toggle(id) }
        case .pasteMarked:
            if model.marks.isEmpty {
                perform(.pasteSelected)
            } else {
                actions.pasteAll(model.markedItems, closePopup: { close(.picked) })
            }
        case .togglePin:
            if let item = model.selectedItem { actions.togglePin(item) }
        case .openSettings:
            close(.other)
            onOpenSettings?()
        case .deleteSelected:
            if let item = model.selectedItem {
                actions.delete(item)
                model.clampSelection()
            }
        case .selectAllText:
            searchField.currentEditor()?.selectAll(nil)
        case .cutText:
            searchField.currentEditor()?.cut(nil)
        case .pasteText:
            searchField.currentEditor()?.paste(nil)
        }
    }

    /// Sets the search text as if typed (used by debug hooks).
    func setQuery(_ text: String) {
        searchField.stringValue = text
        model.query = text
    }

    /// A dock button was clicked.
    func handleDock(_ item: DockItem) {
        switch item {
        case .history: model.scope = .history
        case .pinned: model.scope = model.scope == .pinned ? .history : .pinned
        case .translate: perform(.translateSelected)
        case .pasteAll: perform(.pasteMarked)
        case .settings: perform(.openSettings)
        case .toggle: model.isCollapsed.toggle()
        }
        if panel.isVisible { panel.makeFirstResponder(searchField) }  // keep typing working after a click
    }

    // MARK: NSWindowDelegate / NSTextFieldDelegate

    func windowDidResignKey(_ notification: Notification) {
        close(.resignedKey)
    }

    func controlTextDidChange(_ obj: Notification) {
        model.isCollapsed = false
        model.query = searchField.stringValue
    }

    // MARK: Private

    /// ⌘T: translate the selected row and show the result under it.
    private func translateSelected() {
        guard let item = model.selectedItem, let id = item.id else { return }
        guard model.translation?.itemID != id else { return }  // already shown or in progress
        guard item.kind == .text || item.kind == .url, let text = item.text else {
            model.translation = RowTranslation(itemID: id, state: .failed("Only text can be translated"))
            return
        }
        model.translation = RowTranslation(itemID: id, state: .working)
        Task {
            let state: RowTranslation.State
            do {
                state = .done(try await translation.translate(text))
            } catch {
                state = .failed(translation.describe(error))
            }
            if model.translation?.itemID == id { model.translation?.state = state }
        }
    }

    private func paste(_ item: ClipItem) {
        actions.paste(item, closePopup: { close(.picked) })
    }

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
                return handled ? nil : event
            }
        }
        if clickMonitor == nil {
            // Global monitors only see clicks in other apps, which is exactly "outside".
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(.clickOutside) }
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel,
              let command = PopupKeymap.command(keyCode: event.keyCode, modifiers: .init(event.modifierFlags))
        else { return false }
        return handle(command)
    }

    /// Runs a key's command. Returns false when the key should go to the search field instead.
    func handle(_ command: PopupCommand) -> Bool {
        // Space marks items only while the search box is empty; otherwise it types a space,
        // so multi-word searches work (Omar's choice, 2026-11-10).
        if command == .toggleMark, !model.query.isEmpty { return false }
        if command != .close { model.isCollapsed = false }  // any action brings the list back
        perform(command)
        return true
    }
}

extension PopupKeymap.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}
