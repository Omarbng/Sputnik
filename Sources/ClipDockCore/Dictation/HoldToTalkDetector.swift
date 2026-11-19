import Foundation

/// What a dictation does with what was said.
public enum DictationMode: String, Sendable, Equatable {
    /// fn: type it.
    case dictate
    /// fn + ⌃: an instruction for the selected text ("translate to Russian", "make it shorter"),
    /// or "insert <saved item>".
    case command
    /// fn + ⇧: type it translated (Russian → English, English → the reply language).
    case translate
}

/// The fn key as a push-to-talk key, like Wispr Flow:
/// - hold fn, speak, release: the text is typed (a hold must last `holdThreshold`)
/// - double-tap fn: hands-free; tap fn again to finish, Esc cancels
/// - add ⌃ while holding for a command, ⇧ to translate
/// - any other key while holding cancels, so fn shortcuts (fn+arrows, fn+⌃+arrows, fn+E, F-keys)
///   keep working and nothing is typed.
///
/// Listening starts the moment fn goes down, so the first word isn't lost; a short tap throws
/// that audio away.
public struct HoldToTalkDetector: Sendable {
    public enum Input: Sendable, Equatable {
        case fnDown(at: TimeInterval)
        case fnUp(at: TimeInterval)
        /// The other modifiers now held.
        case modifiers(Set<TapModifier>)
        /// Any key except fn and the modifiers, or Esc (`isEscape`).
        case key(isEscape: Bool)
        /// Called regularly (every ~50 ms) while fn is down or after a tap.
        case tick(at: TimeInterval)
    }

    public enum Output: Sendable, Equatable {
        /// Start listening (fn went down).
        case begin
        /// It's a real hold, or hands-free started: show the pill.
        case confirm(handsFree: Bool)
        /// Stop and use what was said.
        case finish(DictationMode)
        /// Stop and throw it away.
        case cancel
        /// ⌃ or ⇧ joined in: the pill shows the new mode.
        case modeChanged(DictationMode)
    }

    private enum State: Sendable, Equatable {
        case idle
        /// fn is down, not yet a hold.
        case pressed(at: TimeInterval, second: Bool)
        /// A confirmed hold.
        case holding
        /// fn was tapped once; a second press may follow.
        case tapped(at: TimeInterval)
        case handsFree
        /// After a cancel or a hands-free finish: ignore everything until fn is up.
        case waitingForRelease
    }

    public var holdThreshold: TimeInterval = 0.3
    public var doubleTapGap: TimeInterval = 0.4

    private var state = State.idle
    private var modifiers: Set<TapModifier> = []
    public private(set) var mode = DictationMode.dictate

    public init() {}

    public var isListening: Bool {
        switch state {
        case .pressed, .holding, .handsFree: true
        case .idle, .tapped, .waitingForRelease: false
        }
    }

    public mutating func handle(_ input: Input) -> [Output] {
        switch input {
        case .fnDown(let time):
            switch state {
            case .idle:
                startMode()
                state = .pressed(at: time, second: false)
                return [.begin]
            case .tapped(let tappedAt):
                startMode()
                state = .pressed(at: time, second: time - tappedAt <= doubleTapGap)
                return [.begin]
            case .handsFree:
                state = .waitingForRelease
                return [.finish(mode)]
            case .pressed, .holding, .waitingForRelease:
                return []
            }

        case .fnUp(let time):
            switch state {
            case .pressed(let start, let second):
                if time - start >= holdThreshold {
                    state = .idle
                    return [.confirm(handsFree: false), .finish(mode)]
                }
                if second {
                    state = .handsFree
                    return [.confirm(handsFree: true)]
                }
                state = .tapped(at: time)
                return [.cancel]
            case .holding:
                state = .idle
                return [.finish(mode)]
            case .waitingForRelease:
                state = .idle
                return []
            case .idle, .tapped, .handsFree:
                return []
            }

        case .tick(let time):
            switch state {
            case .pressed(let start, _) where time - start >= holdThreshold:
                state = .holding
                return [.confirm(handsFree: false)]
            case .tapped(let tappedAt) where time - tappedAt > doubleTapGap:
                state = .idle
                return []
            default:
                return []
            }

        case .modifiers(let held):
            switch state {
            case .pressed, .holding, .handsFree:
                if held.contains(.command) || held.contains(.option) {
                    return cancel()  // fn+⌘ / fn+⌥ are someone else's shortcuts
                }
                modifiers.formUnion(held)
                let newMode = Self.mode(for: modifiers)
                guard newMode != mode else { return [] }
                mode = newMode
                return [.modeChanged(newMode)]
            case .idle, .tapped, .waitingForRelease:
                return []
            }

        case .key(let isEscape):
            switch state {
            case .pressed, .holding:
                return cancel()
            case .handsFree:
                // Hands-free keeps listening while Omar does other things; only Esc stops it.
                guard isEscape else { return [] }
                state = .idle
                return [.cancel]
            case .tapped:
                state = .idle
                return []
            case .idle, .waitingForRelease:
                return []
            }
        }
    }

    private mutating func startMode() {
        modifiers = []
        mode = .dictate
    }

    private mutating func cancel() -> [Output] {
        state = .waitingForRelease
        return [.cancel]
    }

    static func mode(for modifiers: Set<TapModifier>) -> DictationMode {
        if modifiers.contains(.control) { return .command }
        if modifiers.contains(.shift) { return .translate }
        return .dictate
    }
}
