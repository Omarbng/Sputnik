import AppKit
import ClipDockCore

/// Captures only while "Paste from Other Apps" is set to Allow. In any other state it doesn't
/// read at all ("Ask" would show an alert on every copy). It re-checks every second instead.
@MainActor
final class CaptureController {
    private let watcher = PasteboardWatcher()
    private let reader = PasteboardReader()
    private let pipeline: CapturePipeline
    private var accessTimer: Timer?

    /// Last seen permission state.
    private(set) var access: NSPasteboard.AccessBehavior
    var onAccessChange: ((NSPasteboard.AccessBehavior) -> Void)?

    var isCapturing: Bool { watcher.isRunning }

    init(pipeline: CapturePipeline) {
        self.pipeline = pipeline
        access = PasteboardAccess.behavior
        watcher.onChange = { [weak self] in self?.pasteboardChanged() }
    }

    func start() {
        Log.capture.notice("pasteboard access=\(self.access.logName, privacy: .public)")
        apply(access)
    }

    /// Re-reads the permission and starts or stops polling to match.
    func refreshAccess() {
        let current = PasteboardAccess.behavior
        guard current != access else { return }
        Log.capture.notice("pasteboard access changed to \(current.logName, privacy: .public)")
        access = current
        apply(current)
        onAccessChange?(current)
    }

    private func apply(_ behavior: NSPasteboard.AccessBehavior) {
        if behavior == .alwaysAllow {
            accessTimer?.invalidate()
            accessTimer = nil
            watcher.start()
        } else {
            watcher.stop()
            startAccessTimer()
        }
    }

    private func startAccessTimer() {
        guard accessTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccess() }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    private func pasteboardChanged() {
        refreshAccess()  // so revoking access in System Settings takes effect before this read
        guard access == .alwaysAllow else { return }
        read(attempt: 1, changeCount: NSPasteboard.general.changeCount)
    }

    /// Some apps clear the pasteboard and only then write (slowly). Later writes don't bump
    /// `changeCount`, so an empty read is retried a couple of times for the same change.
    private static let emptyRetryDelay: TimeInterval = 0.3
    private static let maxReadAttempts = 3

    private func read(attempt: Int, changeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == changeCount, access == .alwaysAllow else { return }

        let rules = SkipRules(ignoredBundleIDs: AppSettings.ignoredBundleIDs)
        let source = NSWorkspace.shared.frontmostApplication
        switch reader.read(pasteboard, rules: rules, source: source, now: .now) {
        case .skipped(.empty) where attempt < Self.maxReadAttempts:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.emptyRetryDelay) { [weak self] in
                self?.read(attempt: attempt + 1, changeCount: changeCount)
            }
        case .skipped(let reason):
            Log.capture.notice("skipped reason=\(reason.logName, privacy: .public)")
        case .captured(let clip):
            pipeline.submit(clip, rules: rules, retention: AppSettings.retention)
        }
    }
}
