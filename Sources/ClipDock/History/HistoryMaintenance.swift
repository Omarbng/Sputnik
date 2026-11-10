import AppKit
import ClipDockCore

/// Whole-history operations: Clear history, and re-applying retention after a settings change.
@MainActor
final class HistoryMaintenance {
    private let database: HistoryDatabase
    private let history: HistoryModel
    private let hud: HUDController

    init(database: HistoryDatabase, history: HistoryModel, hud: HUDController) {
        self.database = database
        self.history = history
        self.hud = hud
    }

    /// Asks first. Pinned items are kept.
    func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This deletes every item except pinned ones. It can't be undone."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearHistory()
    }

    func clearHistory() {
        do {
            let removed = try database.clearUnpinned()
            history.remove(ids: removed)
            hud.show("History cleared")
            Log.storage.notice("cleared items=\(removed.count, privacy: .public)")
        } catch {
            hud.show("Couldn't clear history", style: .error)
            Log.storage.error("clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies the current limits now (after they change in Settings).
    func applyRetention() {
        do {
            let removed = try database.applyRetention(AppSettings.retention, now: .now)
            history.remove(ids: removed)
            Log.storage.notice("retention applied removed=\(removed.count, privacy: .public)")
        } catch {
            Log.storage.error("retention failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
