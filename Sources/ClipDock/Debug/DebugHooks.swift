#if DEBUG
import AppKit
import ApplicationServices
import ClipDockCore

/// Debug builds only, and only when launched with `open --env CLIPDOCK_DEBUG_HOOKS=1 …`.
/// Lets a test script drive the popup without Accessibility permission, by posting
/// distributed notifications named `com.omar.clipdock.debug.<name>`:
///   toggle                         open or close the popup at the mouse cursor
///   query  {text}                  set the search text
///   key    {keyCode, command}      press a key through the popup's keymap
///   state                          log the popup state (ids, counts, on-screen check)
///   translateInPlace               same as ⌥⌘T
///   translateShowOnly              same as ⇧⌥⌘T
///   openSettings / closeSettings   the Settings window
///   clearHistoryNow                Clear history without the confirmation alert
///   pause {seconds} / resume       Pause capture (seconds < 0: until resumed)
///   settingsState                  log the saved settings
///   dock {text: name}              press a dock button (history, pinned, translate, pasteAll, settings, toggle)
///   hover {text: name}             pretend the pointer is over a dock button ("" clears it)
///   snapshot {text: path}          render the popup to a PNG (the behind-window blur doesn't render)
///   focused {text}                 log whether the focused text field contains `text`
///                                  (a yes/no only; the field's text is never logged)
@MainActor
final class DebugHooks {
    private var tokens: [NSObjectProtocol] = []

    struct Targets {
        let popup: PopupController
        let translation: TranslationService
        let settings: SettingsWindowController
        let maintenance: HistoryMaintenance
        let capture: CaptureController
    }

    init(targets: Targets) {
        let popup = targets.popup
        let translation = targets.translation
        observe("openSettings") { _ in targets.settings.show() }
        observe("closeSettings") { _ in targets.settings.close() }
        observe("clearHistoryNow") { _ in targets.maintenance.clearHistory() }
        observe("pause") { info in
            let seconds = info.seconds ?? -1
            targets.capture.pause(for: seconds < 0 ? nil : seconds)
        }
        observe("resume") { _ in targets.capture.resumeCapture() }
        observe("settingsState") { _ in
            Log.app.notice("""
                debug settings maxItems=\(AppSettings.maxUnpinnedItems, privacy: .public) \
                days=\(AppSettings.retentionDays, privacy: .public) \
                separator=\(AppSettings.pasteAllSeparator.rawValue, privacy: .public) \
                ignoredApps=\(AppSettings.ignoredBundleIDs.joined(separator: ","), privacy: .public) \
                paused=\(targets.capture.pausedUntil.map { $0 == .distantFuture ? "untilResumed" : "timed" } ?? "no", privacy: .public) \
                settingsOpen=\(targets.settings.isShowing, privacy: .public)
                """)
        }
        observe("toggle") { _ in popup.toggle() }
        observe("dock") { info in
            if let item = Self.dockItem(info.text) { popup.handleDock(item) }
        }
        observe("hover") { info in popup.model.hoveredDockItem = Self.dockItem(info.text) }
        observe("snapshot") { info in
            guard let path = info.text, let view = popup.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            Log.app.notice("debug snapshot written")
        }
        observe("translateInPlace") { _ in translation.translateSelectionInPlace() }
        observe("translateShowOnly") { _ in translation.translateSelectionShowOnly() }
        observe("query") { info in popup.setQuery(info.text ?? "") }
        observe("key") { info in
            guard let keyCode = info.keyCode else { return }
            let modifiers: PopupKeymap.Modifiers = info.command ? .command : []
            if let command = PopupKeymap.command(keyCode: keyCode, modifiers: modifiers), !popup.handle(command) {
                Log.popup.notice("debug key passed to the search field")
            }
        }
        observe("state") { _ in
            let model = popup.model
            let ids = model.sections.all.prefix(10).compactMap(\.id).map(String.init).joined(separator: ",")
            Log.popup.notice("""
                debug state visible=\(popup.isVisible, privacy: .public) \
                queryLength=\(model.query.count, privacy: .public) \
                rows=\(model.sections.all.count, privacy: .public) \
                selected=\(model.selectedIndex, privacy: .public) \
                selectedID=\(model.selectedItem?.id ?? -1, privacy: .public) \
                ids=\(ids, privacy: .public) \
                marks=\(model.marks.ids.map(String.init).joined(separator: ","), privacy: .public) \
                pinned=\(model.sections.pinned.compactMap(\.id).map(String.init).joined(separator: ","), privacy: .public) \
                frame=\(NSStringFromRect(popup.frame), privacy: .public) \
                onScreen=\(popup.isFullyOnScreen, privacy: .public) \
                translation=\(Self.describe(model.translation), privacy: .public)
                """)
        }
        observe("focused") { info in
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            let value = Self.focusedFieldValue()
            Log.popup.notice("""
                debug focused app=\(app, privacy: .public) \
                readable=\(value != nil, privacy: .public) \
                contains=\(value?.contains(info.text ?? "\u{0}") ?? false, privacy: .public)
                """)
        }
        Log.app.notice("debug hooks ready")
    }

    private static func dockItem(_ name: String?) -> DockItem? {
        ["history": DockItem.history, "pinned": .pinned, "translate": .translate,
         "pasteAll": .pasteAll, "settings": .settings, "toggle": .toggle][name ?? ""]
    }

    /// State and length only, never the text.
    private static func describe(_ translation: RowTranslation?) -> String {
        guard let translation else { return "none" }
        switch translation.state {
        case .working: return "working(id=\(translation.itemID))"
        case .done(let text): return "done(id=\(translation.itemID),chars=\(text.count))"
        case .failed: return "failed(id=\(translation.itemID))"
        }
    }

    private static func focusedFieldValue() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// The few values the hooks read, copied out of `userInfo` so they can cross isolation.
    private struct Payload: Sendable {
        var text: String?
        var keyCode: UInt16?
        var command: Bool
        var seconds: Double?
    }

    private func observe(_ name: String, _ handler: @escaping @MainActor (Payload) -> Void) {
        let token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.omar.clipdock.debug." + name), object: nil, queue: .main
        ) { notification in
            let info = notification.userInfo ?? [:]
            let payload = Payload(
                text: info["text"] as? String,
                keyCode: (info["keyCode"] as? NSNumber)?.uint16Value,
                command: info["command"] as? Bool ?? false,
                seconds: (info["seconds"] as? NSNumber)?.doubleValue
            )
            MainActor.assumeIsolated { handler(payload) }
        }
        tokens.append(token)
    }
}
#endif
