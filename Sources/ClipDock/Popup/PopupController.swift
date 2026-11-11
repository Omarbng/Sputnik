import AppKit
import ClipDockCore
import SwiftUI

/// Owns the popup. The panel is created once at launch and then only shown and hidden, so
/// opening is instant. It closes on Esc, a click outside, picking an item, or losing focus.
/// Keys go to one of three modes: the list, the actions menu, or the editor.
@MainActor
final class PopupController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    let model: PopupViewModel
    let panel = PopupPanel()
    let searchField = NSTextField.popupSearchField()
    let editorFields = EditorFields()
    let actions: ItemActions
    let saved: SavedItems
    let translation: TranslationService
    private var keyMonitor: Any?
    private var rightClickMonitor: Any?
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
        actions: ItemActions, saved: SavedItems, translation: TranslationService
    ) {
        let model = PopupViewModel(history: history)
        self.model = model
        self.actions = actions
        self.saved = saved
        self.translation = translation
        super.init()

        let root = PopupRootView(
            model: model, icons: icons, thumbnails: thumbnails, searchField: searchField,
            editorFields: editorFields,
            onDock: { [weak self] item in self?.handleDock(item) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []  // fixed-size panel: SwiftUI must not resize the window
        model.onPick = { [weak self] item in self?.paste(item) }
        model.onShowActions = { [weak self] item in self?.showActions(for: item) }
        model.onRequestDelete = { [weak self] item in self?.requestDelete(item) }
        model.onRunAction = { [weak self] action, item in self?.run(action, on: item) }
        model.onEditorCommand = { [weak self] command in self?.handleEditor(command) }
        model.onNewSaved = { [weak self] in self?.perform(.newSaved) }
        model.onSaveCopiedSecret = { [weak self] in self?.saveCopiedAsSecret() }
        editorFields.onSubmitSecret = { [weak self] in self?.handleEditor(.save) }
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
        editorFields.clear()  // a half-typed secret must not linger
        model.editor = nil
        model.actionMenu = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        Log.popup.notice("closed reason=\(reason.rawValue, privacy: .public)")
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
        case .saved: model.scope = model.scope == .saved ? .history : .saved
        case .secrets: model.scope = model.scope == .secrets ? .history : .secrets
        case .translate: perform(.translateSelected)
        case .settings: perform(.openSettings)
        case .toggle: model.isCollapsed.toggle()
        }
        if panel.isVisible, model.editor == nil { panel.makeFirstResponder(searchField) }  // keep typing working
    }

    // MARK: NSWindowDelegate / NSTextFieldDelegate

    func windowDidResignKey(_ notification: Notification) {
        close(.resignedKey)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === searchField else { return }
        model.isCollapsed = false
        model.actionMenu = nil
        model.query = searchField.stringValue
    }

    // MARK: Keys and clicks

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
                return handled ? nil : event
            }
        }
        if rightClickMonitor == nil {
            rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handleRightClick(event) ?? false }
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
        for monitor in [keyMonitor, rightClickMonitor, clickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        rightClickMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        let modifiers = PopupKeymap.Modifiers(event.modifierFlags)
        if model.editor != nil {
            guard let command = EditorKeymap.command(keyCode: event.keyCode, modifiers: modifiers) else { return false }
            handleEditor(command)
            return true
        }
        guard let command = PopupKeymap.command(keyCode: event.keyCode, modifiers: modifiers) else {
            return model.actionMenu != nil  // typing doesn't reach the search while the menu is open
        }
        return handle(command)
    }

    /// A right-click on a row opens its actions menu.
    private func handleRightClick(_ event: NSEvent) -> Bool {
        guard event.window === panel, model.editor == nil,
              let id = model.hoveredItemID, let item = model.item(id: id)
        else { return false }
        showActions(for: item)
        return true
    }

    /// Runs a key's command. Returns false when the key should go to the search field instead.
    func handle(_ command: PopupCommand) -> Bool {
        if model.actionMenu != nil { return handleInMenu(command) }
        // Space marks items only while the search box is empty; otherwise it types a space,
        // so multi-word searches work (Omar's choice, 2026-11-10).
        if command == .toggleMark, !model.query.isEmpty { return false }
        if command != .close { model.isCollapsed = false }  // any action brings the list back
        if command != .deleteSelected { model.pendingDeleteID = nil }
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
