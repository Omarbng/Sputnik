import AppKit
import SputnikCore

/// Paste one by one (⇧⌘↩ on marked items): the first item is pasted at once, the next waits on
/// the clipboard, and every ⌘V Omar presses in any app moves the stack on. When the last one is
/// pasted, the clipboard goes back to what it was. Copying something else, ten minutes without
/// a paste, or "Stop Paste Stack" in the menu ends it early.
@MainActor
final class PasteStackController {
    /// Time for the app to read the clipboard after ⌘V before the next item replaces it.
    static let advanceDelay: Duration = .milliseconds(300)
    static let idleTimeout: TimeInterval = 10 * 60

    private let database: HistoryDatabase
    private let history: HistoryModel
    private let paster: Paster
    private let hud: HUDController
    private let capture: CaptureController
    private var stack: PasteStack?
    private var snapshot: PasteboardSnapshot?
    private var keyMonitor: Any?
    private var watchTimer: Timer?
    /// The clipboard's change count after Sputnik's last write; anything else means Omar copied.
    private var expectedChangeCount = 0
    private var lastActivity = Date.now

    /// Called when the stack starts or ends (the menu shows "Stop Paste Stack").
    var onChange: (() -> Void)?

    var isActive: Bool { stack != nil }
    var progress: String? { stack?.progress }

    init(database: HistoryDatabase, history: HistoryModel, paster: Paster, hud: HUDController, capture: CaptureController) {
        self.database = database
        self.history = history
        self.paster = paster
        self.hud = hud
        self.capture = capture
    }

    /// Returns false (and says why) when there aren't at least two pastable items.
    @discardableResult
    func start(_ items: [ClipItem], closePopup: () -> Void) -> Bool {
        let usable = items.filter { !$0.isSecret }
        guard let stack = PasteStack(ids: usable.compactMap(\.id)) else {
            hud.show("Mark two or more items with Space first", style: .error)
            return false
        }
        stop(restore: true)
        capture.beginIgnoringChanges()
        snapshot = PasteboardSnapshot.take()
        capture.endIgnoringChanges()
        self.stack = stack
        guard write(stack.current) else { return false }
        closePopup()
        paster.pasteIntoFrontApp()
        Log.paste.notice("stack started count=\(stack.ids.count, privacy: .public)")
        onChange?()
        // Give the first paste time to land before the second item takes its place.
        Task {
            try? await Task.sleep(for: Paster.delay + Self.advanceDelay)
            advance()
            installMonitors()
        }
        return true
    }

    /// Ends the stack. `restore` puts back the clipboard from before it started.
    func stop(restore: Bool) {
        guard stack != nil else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        watchTimer?.invalidate()
        watchTimer = nil
        stack = nil
        if restore, let snapshot {
            capture.beginIgnoringChanges()
            snapshot.restore()
            capture.endIgnoringChanges()
        }
        snapshot = nil
        Log.paste.notice("stack ended restored=\(restore, privacy: .public)")
        onChange?()
    }

    /// For debug hooks: what a ⌘V in another app does.
    func pasted() {
        guard stack != nil else { return }
        Task {
            try? await Task.sleep(for: Self.advanceDelay)
            advance()
        }
    }

    private func advance() {
        guard var stack else { return }
        lastActivity = .now
        guard let next = stack.advance() else {
            self.stack = stack
            stop(restore: true)
            hud.show("Paste stack done")
            return
        }
        self.stack = stack
        if write(next) {
            hud.show("Next: \(stack.progress) — press ⌘V")
        }
    }

    private func write(_ id: Int64?) -> Bool {
        guard let id, let item = history.item(id: id), PasteboardWriter.write(item, blobs: database.blobs) else {
            stop(restore: true)
            hud.show("That item is gone", style: .error)
            return false
        }
        expectedChangeCount = NSPasteboard.general.changeCount
        return true
    }

    private func installMonitors() {
        guard stack != nil, keyMonitor == nil else { return }
        // ⌘V anywhere (by key code, so any keyboard layout). Our own ⌘V for the first item was
        // sent before this monitor existed.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isPaste = event.keyCode == 9 && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            guard isPaste else { return }
            MainActor.assumeIsolated { self?.pasted() }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    /// Omar copied something else, or the stack sat unused: end it (keeping a new copy).
    private func check() {
        guard stack != nil else { return }
        if NSPasteboard.general.changeCount != expectedChangeCount {
            stop(restore: false)
            hud.show("Paste stack stopped")
        } else if Date.now.timeIntervalSince(lastActivity) > Self.idleTimeout {
            stop(restore: true)
        }
    }
}
