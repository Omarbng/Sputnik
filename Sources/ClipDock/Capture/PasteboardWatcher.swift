import AppKit

/// Polls the pasteboard's change count every 0.3 s, because macOS has no "clipboard changed"
/// event. Reading `changeCount` doesn't read contents, so it never triggers a privacy prompt.
@MainActor
final class PasteboardWatcher {
    static let interval: TimeInterval = 0.3

    var onChange: (() -> Void)?

    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    var isRunning: Bool { timer != nil }

    /// Starts polling. Whatever is on the pasteboard right now is not captured.
    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)  // keep firing while menus are open
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Treats the pasteboard's current state as already seen.
    func skipPendingChanges() {
        lastChangeCount = pasteboard.changeCount
    }

    private func tick() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        onChange?()
    }
}
