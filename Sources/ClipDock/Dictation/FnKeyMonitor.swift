import AppKit
import ClipDockCore

/// Watches the talk keys system-wide for dictation, through `HoldToTalkDetector`: fn (🌐), and
/// right ⌥ when that switch is on. Like the double-tap monitor, it needs Accessibility to see
/// other apps' key events. It only watches; the keys still do whatever they normally do (set
/// "Press 🌐 key to" to "Do Nothing").
///
/// Right ⌥ is also a typing key (⌥ + letter) and half of ⌥⌥, so it goes through
/// `DelayedHoldKey`: it starts listening only once held 0.2 s on its own, never makes
/// hands-free, and a click while holding it cancels (⌥-click is a Finder shortcut).
@MainActor
final class FnKeyMonitor {
    var onOutput: ((HoldToTalkDetector.Output) -> Void)?

    /// Which key is driving the detector right now.
    private enum Trigger {
        case fn, rightOption
    }

    /// An event, read off the main thread and handled on it.
    private struct KeyEvent: Sendable {
        enum Kind: Sendable { case flags, key, click }
        let kind: Kind
        let keyCode: UInt16
        let flags: UInt
        let time: TimeInterval
    }

    private var detector = HoldToTalkDetector()
    private var rightOption = DelayedHoldKey()
    private var trigger: Trigger?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var ticker: Timer?
    private nonisolated static let fnKeyCode: UInt16 = 63  // kVK_Function
    private nonisolated static let rightOptionKeyCode: UInt16 = 61  // kVK_RightOption
    private nonisolated static let escapeKeyCode: UInt16 = 53
    /// NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK: which ⌥ is down.
    private nonisolated static let leftOptionBit: UInt = 0x20
    private nonisolated static let rightOptionBit: UInt = 0x40

    var isListening: Bool { detector.isListening }

    func start() {
        stop()
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            let keyEvent = Self.keyEvent(for: event)
            MainActor.assumeIsolated { self?.handle(keyEvent) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            let keyEvent = Self.keyEvent(for: event)
            MainActor.assumeIsolated { self?.handle(keyEvent) }
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
        for input in inputs {
            if case .fnDown = input, trigger == nil { trigger = .fn }
            if case .fnUp = input, trigger == .fn { trigger = nil }
        }
        feed(inputs)
    }

    #if DEBUG
    /// Debug hooks: right ⌥ down or up, or a click, through the same path as real events.
    func simulateRightOption(_ action: String) {
        let now = ProcessInfo.processInfo.systemUptime
        switch action {
        case "down": handleRightOption(down: true, held: [.option], time: now)
        case "up": handleRightOption(down: false, held: [], time: now)
        case "click": handle(KeyEvent(kind: .click, keyCode: 0, flags: 0, time: now))
        default: break
        }
    }
    #endif

    // MARK: Events

    private func handle(_ event: KeyEvent) {
        let held = Self.modifiers(in: event.flags)
        switch event.kind {
        case .key:
            _ = rightOption.handle(.otherInput)
            feed([.key(isEscape: event.keyCode == Self.escapeKeyCode)])
        case .click:
            _ = rightOption.handle(.otherInput)
            if trigger == .rightOption { feed([.key(isEscape: false)]) }
        case .flags:
            if event.keyCode == Self.fnKeyCode {
                handleFn(down: event.flags & NSEvent.ModifierFlags.function.rawValue != 0, held: held, time: event.time)
            } else if event.keyCode == Self.rightOptionKeyCode,
                      trigger == .rightOption || (trigger != .fn && AppSettings.isOn(.rightOptionTalk)) {
                handleRightOption(down: event.flags & Self.rightOptionBit != 0, held: held, time: event.time)
            } else {
                feed([.modifiers(heldForDetector(held, flags: event.flags))])
            }
        }
        updateTicker()
    }

    private func handleFn(down: Bool, held: Set<TapModifier>, time: TimeInterval) {
        if down {
            guard trigger == nil else { return }
            trigger = .fn
            feed([.fnDown(at: time), .modifiers(held)])
        } else {
            guard trigger != .rightOption else { return }
            trigger = nil
            feed([.fnUp(at: time)])
        }
    }

    private func handleRightOption(down: Bool, held: Set<TapModifier>, time: TimeInterval) {
        if down {
            // Only on its own: right ⌥ with ⌘, ⌃ or ⇧ already down is a shortcut.
            guard held == [.option], trigger == nil else { return }
            _ = rightOption.handle(.down(at: time))
        } else if case .ended(let at) = rightOption.handle(.up(at: time)), trigger == .rightOption {
            trigger = nil
            feed([.fnUp(at: at)])
        }
        updateTicker()
    }

    /// While right ⌥ is the talk key, its own ⌥ isn't a modifier (it would cancel).
    private func heldForDetector(_ held: Set<TapModifier>, flags: UInt) -> Set<TapModifier> {
        guard trigger == .rightOption, flags & Self.leftOptionBit == 0 else { return held }
        return held.subtracting([.option])
    }

    private func feed(_ inputs: [HoldToTalkDetector.Input]) {
        for input in inputs {
            for output in detector.handle(input) {
                onOutput?(output)
            }
        }
        updateTicker()
    }

    // MARK: Clock

    /// The clock runs only while a talk key is down, right after a tap, or while right ⌥ may
    /// become a hold.
    private func updateTicker() {
        guard trigger != nil || detector.isListening || rightOption.isPending else { return }
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if case .began(let at) = rightOption.handle(.tick(at: now)), trigger == nil {
            trigger = .rightOption
            Log.dictation.notice("hold key=rightOption")
            let flags = NSEvent.modifierFlags.rawValue
            feed([.fnDown(at: at, allowsHandsFree: false), .modifiers(heldForDetector(Self.modifiers(in: flags), flags: flags))])
        }
        feed([.tick(at: now)])
        if trigger == nil, !detector.isListening, !rightOption.isPending { stopTicking() }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: Reading events

    private nonisolated static func keyEvent(for event: NSEvent) -> KeyEvent {
        let kind: KeyEvent.Kind = switch event.type {
        case .flagsChanged: .flags
        case .keyDown: .key
        default: .click
        }
        return KeyEvent(
            kind: kind,
            keyCode: kind == .click ? 0 : event.keyCode,
            flags: event.modifierFlags.rawValue,
            time: event.timestamp
        )
    }

    private nonisolated static func modifiers(in raw: UInt) -> Set<TapModifier> {
        let flags = NSEvent.ModifierFlags(rawValue: raw)
        var held: Set<TapModifier> = []
        if flags.contains(.option) { held.insert(.option) }
        if flags.contains(.control) { held.insert(.control) }
        if flags.contains(.command) { held.insert(.command) }
        if flags.contains(.shift) { held.insert(.shift) }
        return held
    }
}
