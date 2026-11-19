import AppKit
import ClipDockCore

/// Watches the fn (🌐) key system-wide for dictation, through `HoldToTalkDetector`. Like the
/// double-tap monitor, it needs Accessibility to see other apps' key events. It only watches;
/// fn still does whatever macOS does with it (set "Press 🌐 key to" to "Do Nothing").
@MainActor
final class FnKeyMonitor {
    var onOutput: ((HoldToTalkDetector.Output) -> Void)?

    private var detector = HoldToTalkDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var ticker: Timer?
    private var fnIsDown = false
    private nonisolated static let fnKeyCode: UInt16 = 63  // kVK_Function
    private nonisolated static let escapeKeyCode: UInt16 = 53

    var isListening: Bool { detector.isListening }

    func start() {
        stop()
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            let input = Self.inputs(for: event)
            MainActor.assumeIsolated { self?.handle(input) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            let input = Self.inputs(for: event)
            MainActor.assumeIsolated { self?.handle(input) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        stopTicking()
    }

    /// Feeds the detector directly (debug hooks), the same way real key events do.
    func simulate(_ inputs: [HoldToTalkDetector.Input]) {
        handle(inputs)
    }

    private func handle(_ inputs: [HoldToTalkDetector.Input]) {
        for input in inputs {
            if case .fnDown = input { fnIsDown = true }
            if case .fnUp = input { fnIsDown = false }
            for output in detector.handle(input) {
                onOutput?(output)
            }
        }
        updateTicker()
    }

    /// The detector needs the clock only while fn is down or right after a tap.
    private func updateTicker() {
        if fnIsDown || detector.isListening {
            guard ticker == nil else { return }
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handle([.tick(at: ProcessInfo.processInfo.systemUptime)])
                    if !self.fnIsDown, !self.detector.isListening { self.stopTicking() }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private nonisolated static func inputs(for event: NSEvent) -> [HoldToTalkDetector.Input] {
        switch event.type {
        case .keyDown:
            return [.key(isEscape: event.keyCode == escapeKeyCode)]
        case .flagsChanged:
            let flags = event.modifierFlags
            var held: Set<TapModifier> = []
            if flags.contains(.option) { held.insert(.option) }
            if flags.contains(.control) { held.insert(.control) }
            if flags.contains(.command) { held.insert(.command) }
            if flags.contains(.shift) { held.insert(.shift) }
            if event.keyCode == fnKeyCode {
                let time = event.timestamp
                return flags.contains(.function)
                    ? [.fnDown(at: time), .modifiers(held)]
                    : [.fnUp(at: time)]
            }
            return [.modifiers(held)]
        default:
            return []
        }
    }
}
