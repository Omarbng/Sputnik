import AppKit
import ClipDockCore

/// What you can do with a history item from the popup: paste it (as it is, as plain text, or
/// cleaned up), copy it, open it, pin it, or delete it.
@MainActor
final class ItemActions {
    private let database: HistoryDatabase
    private let history: HistoryModel
    private let paster: Paster
    private let hud: HUDController
    private let translation: TranslationService
    private let capture: CaptureController
    private let secrets: SecretActions

    init(
        database: HistoryDatabase, history: HistoryModel, paster: Paster, hud: HUDController,
        translation: TranslationService, capture: CaptureController, secrets: SecretActions
    ) {
        self.database = database
        self.history = history
        self.paster = paster
        self.hud = hud
        self.translation = translation
        self.capture = capture
        self.secrets = secrets
    }

    /// 1. write to the pasteboard (marked internal) 2. close the popup 3–4. wait, send ⌘V.
    /// Secrets ask for Touch ID first (see `SecretActions`).
    func paste(_ item: ClipItem, closePopup: () -> Void) {
        if item.isSecret {
            let target = NSWorkspace.shared.frontmostApplication
            closePopup()
            secrets.paste(item, into: target, onUsed: { [weak self] in self?.markUsed(item) })
            return
        }
        let written = write(item)
        closePopup()
        guard written else { return }
        markUsed(item)
        paster.pasteIntoFrontApp()
        Log.paste.notice("paste id=\(item.id ?? -1, privacy: .public) kind=\(item.kind.rawValue, privacy: .public)")
    }

    /// Copies without pasting.
    func copy(_ item: ClipItem, closePopup: () -> Void) {
        if item.isSecret {
            closePopup()
            secrets.copy(item, onUsed: { [weak self] in self?.markUsed(item) })
            return
        }
        let written = write(item)
        closePopup()
        guard written else { return }
        markUsed(item)
        hud.show("Copied")
        Log.paste.notice("copy id=\(item.id ?? -1, privacy: .public)")
    }

    /// ⌥↩: the text without its formatting, or a file's path.
    func pastePlain(_ item: ClipItem, closePopup: () -> Void) {
        guard let text = Self.plainText(of: item) else {
            closePopup()
            hud.show(item.isSecret ? "Secrets paste with ↩" : "Images have no text", style: .error)
            return
        }
        PasteboardWriter.write(text: text)
        closePopup()
        markUsed(item)
        paster.pasteIntoFrontApp()
        Log.paste.notice("paste plain id=\(item.id ?? -1, privacy: .public)")
    }

    /// Pastes text made from an item (cleaned up, or edited) and adds it to history, since it's
    /// what you now have in your document.
    func pasteDerived(_ text: String, closePopup: () -> Void) {
        let target = NSWorkspace.shared.frontmostApplication
        PasteboardWriter.write(text: text)
        closePopup()
        capture.record(CapturedClip(
            payload: .fromText(text, rtf: nil),
            sourceBundleID: target?.bundleIdentifier,
            sourceAppName: target?.localizedName,
            capturedAt: .now
        ))
        paster.pasteIntoFrontApp()
        Log.paste.notice("paste derived chars=\(text.count, privacy: .public)")
    }

    /// ⌘C on a rewrite shown under a row: copies it and adds it to history.
    func copyDerived(_ text: String, closePopup: () -> Void) {
        let target = NSWorkspace.shared.frontmostApplication
        PasteboardWriter.write(text: text)
        closePopup()
        capture.record(CapturedClip(
            payload: .fromText(text, rtf: nil),
            sourceBundleID: target?.bundleIdentifier,
            sourceAppName: target?.localizedName,
            capturedAt: .now
        ))
        hud.show("Copied")
    }

    /// ⌘O: opens a link in the default browser, or shows files in Finder.
    func open(_ item: ClipItem, closePopup: () -> Void) {
        switch item.kind {
        case .url:
            guard let url = URL(string: item.text ?? "") else { return }
            closePopup()
            NSWorkspace.shared.open(url)
        case .file:
            let urls = (item.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
                .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            closePopup()
            guard !urls.isEmpty else {
                hud.show("That file isn't there any more", style: .error)
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .text, .image, .secret:
            hud.show("Only links and files open", style: .error)
            return
        }
        markUsed(item)
        Log.paste.notice("open id=\(item.id ?? -1, privacy: .public) kind=\(item.kind.rawValue, privacy: .public)")
    }

    /// A short message at the cursor, for popup actions that can't run.
    func notify(_ message: String) {
        hud.show(message, style: .error)
    }

    /// ↩ on a ⌘T translation: paste it, and add it to history with the translated badge.
    func pasteTranslation(_ text: String, closePopup: () -> Void) {
        let target = NSWorkspace.shared.frontmostApplication
        PasteboardWriter.write(text: text)
        closePopup()
        translation.record(text, from: target)
        paster.pasteIntoFrontApp()
        Log.paste.notice("paste translation chars=\(text.count, privacy: .public)")
    }

    /// ⌘C on a ⌘T translation.
    func copyTranslation(_ text: String, closePopup: () -> Void) {
        let target = NSWorkspace.shared.frontmostApplication
        PasteboardWriter.write(text: text)
        closePopup()
        translation.record(text, from: target)
        hud.show("Copied")
    }

    /// ⌘↩: joins the items' text in the given order with the chosen separator, then pastes once.
    func pasteAll(_ items: [ClipItem], closePopup: () -> Void) {
        let separator = AppSettings.pasteAllSeparator
        let (text, skipped) = PasteAll.join(items, separator: separator)
        guard !text.isEmpty else {
            closePopup()
            hud.show("Nothing to paste as text", style: .error)
            return
        }
        PasteboardWriter.write(text: text)
        closePopup()
        for item in items.reversed() { markUsed(item) }  // the first marked ends up on top
        paster.pasteIntoFrontApp()
        if skipped > 0 { hud.show("Images were left out") }
        Log.paste.notice("""
            paste all ids=\(items.compactMap(\.id).map(String.init).joined(separator: ","), privacy: .public) \
            separator=\(separator.rawValue, privacy: .public) skipped=\(skipped, privacy: .public)
            """)
    }

    /// ⌘P
    func togglePin(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            if let updated = try database.setPinned(!item.isPinned, id: id) {
                history.update(updated)
                Log.storage.notice("pinned id=\(id, privacy: .public) pinned=\(updated.isPinned, privacy: .public)")
            }
        } catch {
            Log.storage.error("pin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes the row; for a secret, its Keychain value too.
    func delete(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            history.remove(ids: try database.delete(ids: [id]))
            Log.storage.notice("deleted id=\(id, privacy: .public) kind=\(item.kind.rawValue, privacy: .public)")
        } catch {
            Log.storage.error("delete failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let account = item.secretRef {
            Task.detached {
                do {
                    try SecretStore.delete(account: account)
                } catch {
                    Log.storage.error("keychain delete failed id=\(id, privacy: .public)")
                }
            }
        }
    }

    /// What ⌥↩ pastes: text as it is (without formatting) or newline-separated file paths.
    static func plainText(of item: ClipItem) -> String? {
        switch item.kind {
        case .text, .url, .file: item.text
        case .image, .secret: nil
        }
    }

    private func write(_ item: ClipItem) -> Bool {
        guard PasteboardWriter.write(item, blobs: database.blobs) else {
            hud.show("Couldn't copy that item", style: .error)
            Log.paste.error("write failed id=\(item.id ?? -1, privacy: .public)")
            return false
        }
        return true
    }

    /// Using an item from history moves it to the top.
    func markUsed(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            if let updated = try database.touch(id: id, now: .now) {
                history.moveToTop(updated)
            }
        } catch {
            Log.storage.error("touch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
