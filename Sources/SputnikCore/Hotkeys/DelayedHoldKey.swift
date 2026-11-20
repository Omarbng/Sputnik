import Foundation

/// A key that's also used for other things (right ⌥: ⌥⌥ opens the clipboard, ⌥ + a letter
/// types a symbol) working as a hold-to-talk key. Its press is passed on only after it has been
/// held `delay` with no key or click in between, so quick taps and ⌥-typing never start the
/// microphone. The press time is passed on unchanged, so hold timing still counts from it.
public struct DelayedHoldKey: Sendable {
    public enum Input: Sendable {
        case down(at: TimeInterval)
        case up(at: TimeInterval)
        /// A key press or a click: the key is being used as a modifier.
        case otherInput
        case tick(at: TimeInterval)
    }

    public enum Output: Equatable, Sendable {
        /// Held long enough: start, as if pressed at `at`.
        case began(at: TimeInterval)
        /// Released after `began`.
        case ended(at: TimeInterval)
    }

    public var delay: TimeInterval = 0.2

    private enum State: Sendable {
        case idle
        case pending(since: TimeInterval)
        case held
        /// Used with another key: ignore it until it's released.
        case blocked
    }

    private var state = State.idle

    public init() {}

    /// True while waiting to see if it's a hold (the caller ticks only then).
    public var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    public mutating func handle(_ input: Input) -> Output? {
        switch (input, state) {
        case (.down(let time), .idle):
            state = .pending(since: time)
            return nil
        case (.down, _):
            return nil
        case (.tick(let now), .pending(let since)) where now - since >= delay:
            state = .held
            return .began(at: since)
        case (.tick, _):
            return nil
        case (.up(let time), .held):
            state = .idle
            return .ended(at: time)
        case (.up, _):
            state = .idle
            return nil
        case (.otherInput, .pending):
            state = .blocked
            return nil
        case (.otherInput, _):
            return nil
        }
    }
}
