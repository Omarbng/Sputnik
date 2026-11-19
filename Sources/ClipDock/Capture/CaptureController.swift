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
    private var resumeTimer: Timer?
    private var suspensions = 0

    /// Last seen permission state.
    private(set) var access: NSPasteboard.AccessBehavior
    var onAccessChange: ((NSPasteboard.AccessBehavior) -> Void)?
    var onPauseChange: (() -> Void)?

    /// True when "Paste from Other Apps" allows reading, so polling runs.
    var hasAccess: Bool { watcher.isRunning }

    /// When a pause ends by itself (`.distantFuture` for "until resumed"), or nil if not paused.
    var pausedUntil: Date? {
        AppSettings.pausedUntil.flatMap { $0 > .now ? $0 : nil }
    }

    var isCapturing: Bool { hasAccess && pausedUntil == nil }

    init(pipeline: CapturePipeline) {
        self.pipeline = pipeline
        access = PasteboardAccess.behavior
        watcher.onChange = { [weak self] in self?.pasteboardChanged() }
    }

    func start() {
        Log.capture.notice("pasteboard access=\(self.access.logName, privacy: .public) paused=\(self.pausedUntil != nil, privacy: .public)")
        if AppSettings.pausedUntil != nil, pausedUntil == nil { AppSettings.pausedUntil = nil }  // expired while quit
        scheduleAutoResume()
        apply(access)
    }

    /// Pause capture for `duration` seconds, or until resumed when nil.
    func pause(for duration: TimeInterval?) {
        AppSettings.pausedUntil = duration.map { Date.now.addingTimeInterval($0) } ?? .distantFuture
        scheduleAutoResume()
        Log.capture.notice("paused for=\(duration.map { String(Int($0)) } ?? "untilResumed", privacy: .public)")
        onPauseChange?()
    }

    func resumeCapture() {
        AppSettings.pausedUntil = nil
        resumeTimer?.invalidate()
        resumeTimer = nil
        watcher.skipPendingChanges()  // what was copied during the pause stays private
        Log.capture.notice("resumed")
        onPauseChange?()
    }

    private func scheduleAutoResume() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        guard let until = pausedUntil, until != .distantFuture else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeCapture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        resumeTimer = timer
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

    /// Ignores pasteboard changes during ClipDock's own work: translation's temporary ⌘C copy
    /// and the restore of the original clipboard. Calls nest; each needs an `endIgnoringChanges()`.
    func beginIgnoringChanges() {
        suspensions += 1
    }

    func endIgnoringChanges() {
        suspensions = max(0, suspensions - 1)
        if suspensions == 0 { watcher.skipPendingChanges() }
    }

    /// Adds something ClipDock made (a translation) to the history.
    func record(_ clip: CapturedClip) {
        pipeline.submit(clip, rules: SkipRules(ignoredBundleIDs: AppSettings.ignoredBundleIDs), retention: AppSettings.retention)
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
        guard access == .alwaysAllow, suspensions == 0, pausedUntil == nil else { return }
        read(attempt: 1, changeCount: NSPasteboard.general.changeCount)
    }

    /// Some apps clear the pasteboard and only then write (slowly). Later writes don't bump
    /// `changeCount`, so an empty read is retried a couple of times for the same change.
    private static let emptyRetryDelay: TimeInterval = 0.3
    private static let maxReadAttempts = 3

    private func read(attempt: Int, changeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == changeCount, access == .alwaysAllow, suspensions == 0, pausedUntil == nil
        else { return }

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
            pipeline.submit(Self.markSensitive(cleanLink(clip, changeCount: changeCount)), rules: rules, retention: AppSettings.retention)
        }
    }

    /// "Clean links": a copied link loses its tracking parameters, in history and on the
    /// clipboard (unless the copy also carries formatted text or an image, which stays as it was).
    private func cleanLink(_ clip: CapturedClip, changeCount: Int) -> CapturedClip {
        guard AppSettings.isOn(.cleanLinks), case .url(let link) = clip.payload,
              let cleaned = LinkCleaner.clean(link)
        else { return clip }
        var copy = clip
        copy.payload = .url(cleaned)
        let pasteboard = NSPasteboard.general
        let types = Set(pasteboard.types ?? [])
        let rich: Set<NSPasteboard.PasteboardType> = [.html, .rtf, .rtfd, .png, .tiff, .fileURL, .pdf]
        if pasteboard.changeCount == changeCount, types.isDisjoint(with: rich) {
            let item = NSPasteboardItem()
            item.setString(cleaned, forType: .string)
            item.setString(cleaned, forType: .URL)
            beginIgnoringChanges()
            PasteboardWriter.write([item])
            endIgnoringChanges()
        }
        Log.capture.notice("link cleaned chars=\(link.count, privacy: .public)->\(cleaned.count, privacy: .public)")
        return copy
    }

    /// "Forget sensitive copies": keys, card numbers, IBANs and codes leave history after 10 minutes.
    private static func markSensitive(_ clip: CapturedClip) -> CapturedClip {
        guard AppSettings.isOn(.expireSensitive), clip.kind == .text || clip.kind == .url,
              let text = clip.storedText, let kind = SensitiveDetector.kind(of: text)
        else { return clip }
        var copy = clip
        copy.expiresAt = clip.capturedAt.addingTimeInterval(SensitiveDetector.lifetime)
        Log.capture.notice("sensitive kind=\(kind.rawValue, privacy: .public) expiresIn=\(Int(SensitiveDetector.lifetime), privacy: .public)s")
        return copy
    }
}
