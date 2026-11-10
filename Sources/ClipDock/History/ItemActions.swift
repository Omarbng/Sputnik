import AppKit
import ClipDockCore

/// What you can do with a history item from the popup: paste it, copy it, or delete it.
@MainActor
final class ItemActions {
    private let database: HistoryDatabase
    private let history: HistoryModel
    private let paster: Paster
    private let hud: HUDController

    init(database: HistoryDatabase, history: HistoryModel, paster: Paster, hud: HUDController) {
        self.database = database
        self.history = history
        self.paster = paster
        self.hud = hud
    }

    /// 1. write to the pasteboard (marked internal) 2. close the popup 3–4. wait, send ⌘V.
    func paste(_ item: ClipItem, closePopup: () -> Void) {
        let written = write(item)
        closePopup()
        guard written else { return }
        markUsed(item)
        paster.pasteIntoFrontApp()
        Log.paste.notice("paste id=\(item.id ?? -1, privacy: .public) kind=\(item.kind.rawValue, privacy: .public)")
    }

    /// Copies without pasting.
    func copy(_ item: ClipItem, closePopup: () -> Void) {
        let written = write(item)
        closePopup()
        guard written else { return }
        markUsed(item)
        hud.show("Copied")
        Log.paste.notice("copy id=\(item.id ?? -1, privacy: .public)")
    }

    func delete(_ item: ClipItem) {
        guard let id = item.id else { return }
        do {
            history.remove(ids: try database.delete(ids: [id]))
            Log.storage.notice("deleted id=\(id, privacy: .public)")
        } catch {
            Log.storage.error("delete failed: \(error.localizedDescription, privacy: .public)")
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
    private func markUsed(_ item: ClipItem) {
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
