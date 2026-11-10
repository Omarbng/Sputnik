import AppKit
import ClipDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = HistoryModel()
    private let accessCard = PasteAccessWindowController()
    private var capture: CaptureController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let database = openDatabase() else { return }

        let history = self.history
        let accessCard = self.accessCard
        let pipeline = CapturePipeline(database: database) { change in history.apply(change) }
        let capture = CaptureController(pipeline: pipeline)
        let statusItem = StatusItemController(
            history: history,
            isCapturing: { [weak capture] in capture?.isCapturing ?? false },
            onAllowAccess: { [weak capture] in accessCard.show(access: capture?.access ?? PasteboardAccess.behavior) }
        )
        capture.onAccessChange = { [weak statusItem] access in
            statusItem?.refreshIcon()
            accessCard.update(access: access)
        }

        capture.start()
        statusItem.refreshIcon()
        self.capture = capture
        self.statusItem = statusItem
        showAccessCardIfNeeded(access: capture.access)
    }

    private func openDatabase() -> HistoryDatabase? {
        do {
            let database = try HistoryDatabase(directory: AppPaths.supportDirectory())
            let expired = try database.applyRetention(AppSettings.retention, now: .now)
            history.replaceAll(with: try database.allItems())
            Log.storage.notice("history loaded items=\(self.history.items.count, privacy: .public) expired=\(expired.count, privacy: .public)")
            return database
        } catch {
            Log.storage.error("cannot open history: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "ClipDock can't open its history"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return nil
        }
    }

    /// The card appears on its own once. After that it's in the menu while capture is off.
    private func showAccessCardIfNeeded(access: NSPasteboard.AccessBehavior) {
        guard access != .alwaysAllow, !AppSettings.didShowPasteAccessCard else { return }
        AppSettings.didShowPasteAccessCard = true
        accessCard.show(access: access)
    }
}
