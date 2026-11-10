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
///   focused {text}                 log whether the focused text field contains `text`
///                                  (a yes/no only; the field's text is never logged)
@MainActor
final class DebugHooks {
    private var tokens: [NSObjectProtocol] = []

    init(popup: PopupController) {
        observe("toggle") { _ in popup.toggle() }
        observe("query") { info in popup.setQuery(info.text ?? "") }
        observe("key") { info in
            guard let keyCode = info.keyCode else { return }
            let modifiers: PopupKeymap.Modifiers = info.command ? .command : []
            if let command = PopupKeymap.command(keyCode: keyCode, modifiers: modifiers) {
                popup.perform(command)
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
                frame=\(NSStringFromRect(popup.frame), privacy: .public) \
                onScreen=\(popup.isFullyOnScreen, privacy: .public)
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
    }

    private func observe(_ name: String, _ handler: @escaping @MainActor (Payload) -> Void) {
        let token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.omar.clipdock.debug." + name), object: nil, queue: .main
        ) { notification in
            let info = notification.userInfo ?? [:]
            let payload = Payload(
                text: info["text"] as? String,
                keyCode: (info["keyCode"] as? NSNumber)?.uint16Value,
                command: info["command"] as? Bool ?? false
            )
            MainActor.assumeIsolated { handler(payload) }
        }
        tokens.append(token)
    }
}
#endif
