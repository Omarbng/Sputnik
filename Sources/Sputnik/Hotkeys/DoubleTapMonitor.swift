import AppKit
import SputnikCore

/// Watches every key and modifier change, system-wide, for double-taps (⌥⌥, ⌃⌃ …). Watching
/// other apps' key events needs the Accessibility permission.
@MainActor
final class DoubleTapMonitor {
    var onDoubleTap: ((TapModifier) -> Void)?

    private var detector = ModifierTapDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private static let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// (Re)installs the monitors. Call it again after Accessibility is granted.
    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] event in
            let input = Self.input(for: event)
            MainActor.assumeIsolated { self?.handle(input) }
        }
        // Our own panels (the popup, the translation card) don't reach the global monitor.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
            let input = Self.input(for: event)
            MainActor.assumeIsolated { self?.handle(input) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ input: ModifierTapDetector.Input) {
        if let modifier = detector.handle(input) {
            Log.app.notice("double tap \(modifier.rawValue, privacy: .public)")
            onDoubleTap?(modifier)
        }
    }

    private nonisolated static func input(for event: NSEvent) -> ModifierTapDetector.Input {
        guard event.type == .flagsChanged else { return .otherInput }
        let flags = event.modifierFlags
        var held: Set<TapModifier> = []
        if flags.contains(.option) { held.insert(.option) }
        if flags.contains(.control) { held.insert(.control) }
        if flags.contains(.command) { held.insert(.command) }
        if flags.contains(.shift) { held.insert(.shift) }
        return .modifiers(held, at: event.timestamp)
    }
}
