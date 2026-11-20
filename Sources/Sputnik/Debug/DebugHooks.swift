#if DEBUG
import AppKit
import ApplicationServices
import SputnikCore

/// Debug builds only, and only when launched with `open --env CLIPDOCK_DEBUG_HOOKS=1 …`.
/// Lets a test script drive the popup without Accessibility permission, by posting
/// distributed notifications named `com.omar.clipdock.debug.<name>`:
///   toggle                         open or close the popup at the mouse cursor
///   query  {text}                  set the search text
///   key    {keyCode, command, option, shift}  press a key through the popup's keymap (or the
///                                  editor's, while it's open)
///   action {text: name}            run a ClipAction (paste, edit, tidy, delete …) on the selected row
///   editorSet {text, field: name|text|secret}  fill an editor field (test values only)
///   editor {text: save|primary|cancel|toggleSecret}  an editor command
///   hoverRow {text: id}            pretend the pointer is over a row ("" clears it)
///   fieldCommand {text: insertNewline|insertTab|insertBacktab}  what ↩/⇥ do in the focused
///                                  editor field, without posting a key (nothing can leak out)
///   rowActions {text: id}          press a row's ⋯ button
///   postKey {keyCode, command, option, shift}  post a real key press through the system
///   postText {text}                post real typing (test values only)
///   postMouse {text: move|left|right, x, y}  post a real mouse event (top-left screen coordinates)
///   state                          log the popup state (ids, counts, on-screen check)
///   translate                      same as the translate shortcut (double-tap ⌃)
///   card {text: replace|copy|close} press a button in the translation card
///   postDoubleTap {text: option|control}  post two real modifier taps through the system,
///                                  to test the double-tap monitor end to end
///   openSettings / closeSettings   the Settings window
///   clearHistoryNow                Clear history without the confirmation alert
///   pause {seconds} / resume       Pause capture (seconds < 0: until resumed)
///   settingsState                  log the saved settings
///   dock {text: name}              press a dock button (history, saved, secrets, translate, settings, toggle)
///   hover {text: name}             pretend the pointer is over a dock button ("" clears it)
///   snapshot {text: path}          render the popup to a PNG (the behind-window blur doesn't render)
///   focused {text}                 log whether the focused text field contains `text`
///                                  (a yes/no only; the field's text is never logged)
///   dictateFile {text: path, field: dictate|command|translate}  a dictation from an audio file
///                                  (no microphone), typed into the test target
///   fn {text: down|up|key|esc|ctrl|shift}  feed the fn monitor directly (no system events, so
///                                  macOS and other fn apps never see it)
///   pillSnapshot {text: path}      render the dictation pill to a PNG
///   stack {text: pasted|stop}      the paste stack: as if ⌘V was pressed, or stop it
///   historyFlags                   log the top items' ids with their badges and expiry
///   appearance {text: dark|light|system}  Sputnik's own appearance (not the system's)
///   cardSnapshot / hudSnapshot {text: path}  render the translation card or the HUD
///   hud {text, field: info|error}  show a HUD message
///   rightOption {text: down|up|click}  right ⌥ as the talk key, fed to the monitor directly
///   proofread                      same as the proofread shortcut (double-tap ⇧)
///   guide / guideClose / guideSnapshot {text: path}  the Shortcuts window
///   setup {text: welcome|languages|permissions|ready} / setupClose / setupSnapshot {text: path}
///   seedDemo                       fill a demo history (only with CLIPDOCK_DATA_DIR) with made-up items
///   pillDemo {text: listening|working|hide, field: dictate|translate|command, seconds: level 0…1}
@MainActor
final class DebugHooks {
    private var tokens: [NSObjectProtocol] = []
    private weak var popup: PopupController?

    /// Hooks that open UI, send input, or paste run only while the test target app is frontmost,
    /// so a test can never type or paste into an app Omar is using.
    static let testTarget = "com.omar.clipdock.testtarget"
    private static let needsTestTarget: Set<String> = [
        "toggle", "dock", "translate", "card", "postDoubleTap", "key", "action", "editor", "fieldCommand", "rowActions",
        "postKey", "postText", "postMouse", "openSettings", "clearHistoryNow", "dictateFile", "fn", "stack", "hud",
        "proofread", "rightOption", "guide", "setup",
    ]
    /// Posted keys and clicks must land in the popup itself.
    private static let needsPopupKey: Set<String> = ["postKey", "postText", "postMouse"]

    struct Targets {
        let popup: PopupController
        let translation: TranslationService
        let card: TranslationCardController
        let settings: SettingsWindowController
        let maintenance: HistoryMaintenance
        let capture: CaptureController
        let dictation: DictationController
        let pasteStack: PasteStackController
        let history: HistoryModel
        let hud: HUDController
        let proofreader: SelectionProofreader
        let guide: GuideWindowController
        let setup: SetupWindowController
        let saved: SavedItems
    }

    init(targets: Targets) {
        let popup = targets.popup
        self.popup = popup
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
        observe("translate") { _ in translation.translateSelection() }
        observe("card") { info in
            let command: [String: PopupCommand] = ["replace": .pasteSelected, "copy": .copySelected, "close": .close]
            if let command = command[info.text ?? ""] { targets.card.perform(command) }
        }
        observe("postDoubleTap") { info in
            guard let modifier = TapModifier(rawValue: info.text ?? "") else { return }
            Task { await Self.postDoubleTap(modifier) }
        }
        observe("query") { info in popup.setQuery(info.text ?? "") }
        observe("key") { info in
            guard let keyCode = info.keyCode else { return }
            var modifiers: PopupKeymap.Modifiers = []
            if info.command { modifiers.insert(.command) }
            if info.option { modifiers.insert(.option) }
            if info.shift { modifiers.insert(.shift) }
            if popup.model.editor != nil {
                if let command = EditorKeymap.command(keyCode: keyCode, modifiers: modifiers) { popup.handleEditor(command) }
            } else if let command = PopupKeymap.command(keyCode: keyCode, modifiers: modifiers), !popup.handle(command) {
                Log.popup.notice("debug key passed to the search field")
            }
        }
        observe("action") { info in
            guard let action = ClipAction(rawValue: info.text ?? ""), let item = popup.model.selectedItem else { return }
            popup.run(action, on: item)
        }
        observe("editorSet") { info in
            let fields = popup.editorFields
            switch info.field {
            case "name": fields.nameField.stringValue = info.text ?? ""
            case "secret": fields.secretField.stringValue = info.text ?? ""
            default: fields.textView.string = info.text ?? ""
            }
        }
        observe("editor") { info in
            let commands: [String: EditorCommand] = ["save": .save, "primary": .primary, "cancel": .cancel, "toggleSecret": .toggleSecret]
            if let command = commands[info.text ?? ""] { popup.handleEditor(command) }
        }
        observe("hoverRow") { info in popup.model.hoveredItemID = info.text.flatMap { Int64($0) } }
        observe("fieldCommand") { info in
            guard let text = popup.panel.firstResponder as? NSTextView else { return }
            text.doCommand(by: NSSelectorFromString((info.text ?? "") + ":"))
        }
        observe("rowActions") { info in
            if let id = info.text.flatMap({ Int64($0) }), let item = popup.model.item(id: id) { popup.model.onShowActions?(item) }
        }
        observe("postKey") { info in
            guard let keyCode = info.keyCode else { return }
            var flags: CGEventFlags = []
            if info.command { flags.insert(.maskCommand) }
            if info.option { flags.insert(.maskAlternate) }
            if info.shift { flags.insert(.maskShift) }
            Self.postKey(CGKeyCode(keyCode), flags: flags)
        }
        observe("postText") { info in
            guard let text = info.text else { return }
            Task { await Self.postText(text) }
        }
        observe("postMouse") { info in
            guard let x = info.x, let y = info.y else { return }
            Self.postMouse(info.text ?? "move", at: CGPoint(x: x, y: y))
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
                saved=\(model.sections.saved.compactMap(\.id).map(String.init).joined(separator: ","), privacy: .public) \
                scope=\(String(describing: model.scope), privacy: .public) \
                kinds=\(model.sections.all.prefix(10).map(\.kind.rawValue).joined(separator: ","), privacy: .public) \
                menu=\(model.actionMenu.map { "\($0.itemID):\($0.actions.map(\.rawValue).joined(separator: "+"))@\($0.highlighted)" } ?? "none", privacy: .public) \
                editor=\(Self.describe(model.editor), privacy: .public) \
                pendingDelete=\(model.pendingDeleteID ?? -1, privacy: .public) \
                hoveredRow=\(model.hoveredItemID ?? -1, privacy: .public) \
                firstResponder=\(Self.describe(popup.panel.firstResponder, popup), privacy: .public) \
                fieldLengths=\(popup.editorFields.name.count, privacy: .public)/\(popup.editorFields.text.count, privacy: .public)/\(popup.editorFields.secret.count, privacy: .public) \
                frame=\(NSStringFromRect(popup.frame), privacy: .public) \
                onScreen=\(popup.isFullyOnScreen, privacy: .public) \
                translation=\(Self.describe(model.translation), privacy: .public) \
                peek=\(model.peekID ?? -1, privacy: .public)
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
        observe("dictateFile") { info in
            guard let path = info.text else { return }
            let mode = DictationMode(rawValue: info.field ?? "dictate") ?? .dictate
            targets.dictation.dictate(file: URL(fileURLWithPath: path), mode: mode)
        }
        observe("fn") { info in
            let now = ProcessInfo.processInfo.systemUptime
            let inputs: [HoldToTalkDetector.Input] = switch info.text ?? "" {
            case "down": [.fnDown(at: now), .modifiers([])]
            case "up": [.fnUp(at: now)]
            case "key": [.key(isEscape: false)]
            case "esc": [.key(isEscape: true)]
            case "ctrl": [.modifiers([.control])]
            case "shift": [.modifiers([.shift])]
            default: []
            }
            targets.dictation.monitor.simulate(inputs)
        }
        observe("rightOption") { info in targets.dictation.monitor.simulateRightOption(info.text ?? "") }
        observe("proofread") { _ in targets.proofreader.proofreadSelection() }
        observe("guide") { _ in targets.guide.show() }
        observe("guideClose") { _ in targets.guide.close() }
        observe("setup") { info in targets.setup.show(step: info.text ?? "welcome") }
        observe("setupClose") { _ in targets.setup.close() }
        observe("seedDemo") { _ in
            guard ProcessInfo.processInfo.environment["CLIPDOCK_DATA_DIR"] != nil else {
                Log.app.notice("debug seedDemo refused: not a demo history")
                return
            }
            DemoContent.seed(capture: targets.capture, saved: targets.saved)
        }
        observe("pillDemo") { info in
            let pill = targets.dictation.pill
            switch info.text ?? "" {
            case "hide": pill.hide()
            default:
                pill.state.mode = switch info.field { case "translate": .translate; case "command": .command; default: .dictate }
                pill.state.phase = info.text == "working" ? .working : .listening
                pill.state.level = Float(info.seconds ?? 0)
                if !pill.isVisible { pill.show() }
            }
        }
        observe("setupSnapshot") { info in
            if let path = info.text { targets.setup.snapshot(to: path) }
        }
        observe("guideSnapshot") { info in
            if let path = info.text { targets.guide.snapshot(to: path) }
        }
        observe("pillSnapshot") { info in
            if let path = info.text { targets.dictation.pill.snapshot(to: path) }
        }
        observe("stack") { info in
            switch info.text {
            case "pasted": targets.pasteStack.pasted()
            case "stop": targets.pasteStack.stop(restore: true)
            default: break
            }
        }
        observe("appearance") { info in
            NSApp.appearance = switch info.text {
            case "dark": NSAppearance(named: .darkAqua)
            case "light": NSAppearance(named: .aqua)
            default: nil
            }
        }
        observe("cardSnapshot") { info in if let path = info.text { targets.card.snapshot(to: path) } }
        observe("hudSnapshot") { info in if let path = info.text { targets.hud.snapshot(to: path) } }
        observe("hudHide") { _ in targets.hud.hide() }
        observe("hud") { info in
            targets.hud.show(info.text ?? "Copied", style: info.field == "error" ? .error : .info, autoHide: false)
        }
        observe("historyFlags") { _ in
            let flags = targets.history.items.prefix(12).map { item in
                var tags: [String] = [item.kind.rawValue]
                if item.isTranslation { tags.append("translated") }
                if item.isDictation { tags.append("dictated") }
                if let expires = item.expiresAt { tags.append("expiresIn=\(Int(expires.timeIntervalSinceNow))s") }
                if item.isPinned { tags.append("saved") }
                return "\(item.id ?? -1):\(tags.joined(separator: "+"))"
            }
            Log.app.notice("debug history \(flags.joined(separator: " "), privacy: .public) stack=\(targets.pasteStack.progress ?? "none", privacy: .public)")
        }
        Log.app.notice("debug hooks ready")
    }

    /// Two press-and-release taps of a modifier, posted at the HID level like a real keyboard.
    private static func postDoubleTap(_ modifier: TapModifier) async {
        let (key, flag): (CGKeyCode, CGEventFlags) = switch modifier {
        case .option: (0x3A, .maskAlternate)
        case .control: (0x3B, .maskControl)
        case .command: (0x37, .maskCommand)
        case .shift: (0x38, .maskShift)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<2 {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
                event.type = .flagsChanged
                event.flags = down ? flag : []
                event.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }

    /// Mode and flags only, never what was typed.
    private static func describe(_ editor: EditorState?) -> String {
        guard let editor else { return "none" }
        let mode = switch editor.mode {
        case .new: "new"
        case .edit(let id): "edit(\(id))"
        }
        return "\(mode),secret=\(editor.isSecret),name=\(editor.showsName),message=\(editor.message != nil)"
    }

    private static func describe(_ responder: NSResponder?, _ popup: PopupController) -> String {
        let fields = popup.editorFields
        guard let responder else { return "none" }
        if let editor = responder as? NSText, let delegate = editor.delegate as? NSTextField {
            if delegate === popup.searchField { return "search" }
            if delegate === fields.nameField { return "name" }
            if delegate === fields.secretField { return "secret" }
        }
        if responder === fields.textView { return "text" }
        return String(describing: type(of: responder))
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func postText(_ text: String) async {
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event?.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private static func postMouse(_ kind: String, at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let types: [(CGEventType, CGMouseButton)] = switch kind {
        case "left": [(.leftMouseDown, .left), (.leftMouseUp, .left)]
        case "right": [(.rightMouseDown, .right), (.rightMouseUp, .right)]
        default: [(.mouseMoved, .left)]
        }
        for (type, button) in types {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
                .post(tap: .cghidEventTap)
        }
    }

    private static func dockItem(_ name: String?) -> DockItem? {
        ["history": DockItem.history, "saved": .saved, "pinned": .saved, "translate": .translate,
         "secrets": .secrets, "settings": .settings, "toggle": .toggle][name ?? ""]
    }

    /// State and length only, never the text.
    private static func describe(_ translation: RowTranslation?) -> String {
        guard let translation else { return "none" }
        switch translation.state {
        case .working: return "working(id=\(translation.itemID))"
        case .done(let text): return "done(id=\(translation.itemID),kind=\(translation.kind),label=\(translation.label ?? "-"),chars=\(text.count))"
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
        var field: String?
        var keyCode: UInt16?
        var command: Bool
        var option: Bool
        var shift: Bool
        var seconds: Double?
        var x: Double?
        var y: Double?
    }

    private func observe(_ name: String, _ handler: @escaping @MainActor (Payload) -> Void) {
        let token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.omar.clipdock.debug." + name), object: nil, queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo ?? [:]
            let payload = Payload(
                text: info["text"] as? String,
                field: info["field"] as? String,
                keyCode: (info["keyCode"] as? NSNumber)?.uint16Value,
                command: info["command"] as? Bool ?? false,
                option: info["option"] as? Bool ?? false,
                shift: info["shift"] as? Bool ?? false,
                seconds: (info["seconds"] as? NSNumber)?.doubleValue,
                x: (info["x"] as? NSNumber)?.doubleValue,
                y: (info["y"] as? NSNumber)?.doubleValue
            )
            MainActor.assumeIsolated {
                guard self?.allows(name) == true else { return }
                handler(payload)
            }
        }
        tokens.append(token)
    }

    private func allows(_ name: String) -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        if Self.needsTestTarget.contains(name), front != Self.testTarget {
            Log.app.notice("debug refused \(name, privacy: .public): front=\(front, privacy: .public)")
            return false
        }
        if Self.needsPopupKey.contains(name), popup?.panel.isKeyWindow != true {
            Log.app.notice("debug refused \(name, privacy: .public): popup isn't key")
            return false
        }
        return true
    }
}
#endif
