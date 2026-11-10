import Foundation

/// A modifier key that can be double-tapped as a shortcut.
public enum TapModifier: String, CaseIterable, Sendable {
    case option, control, command, shift

    public var symbol: String {
        switch self {
        case .option: "⌥"
        case .control: "⌃"
        case .command: "⌘"
        case .shift: "⇧"
        }
    }

    public var name: String {
        switch self {
        case .option: "Option"
        case .control: "Control"
        case .command: "Command"
        case .shift: "Shift"
        }
    }
}

/// Recognises "tap a modifier key twice, quickly, on its own" (like Wispr Flow's one-key
/// shortcuts). A tap is a press and release of exactly one modifier with nothing else in
/// between. Holding it for a combo (⌥⌘T), typing with it (⌥E for an accent), or clicking
/// while holding it doesn't count. The shortcut fires when the second tap is released.
public struct ModifierTapDetector: Sendable {
    public enum Input: Sendable {
        /// The modifiers now held (after a press or release).
        case modifiers(Set<TapModifier>, at: TimeInterval)
        /// Any key press or mouse click.
        case otherInput
    }

    /// Longest press that still counts as a tap.
    public var maxPressDuration: TimeInterval = 0.35
    /// Longest pause between the first release and the second press.
    public var maxGap: TimeInterval = 0.4

    private var pressed: (modifier: TapModifier, at: TimeInterval)?
    private var firstTap: (modifier: TapModifier, releasedAt: TimeInterval)?
    /// After a combo or a key press, ignore everything until every modifier is up again.
    private var blockedUntilAllReleased = false

    public init() {}

    /// Feed every modifier change, key press, and click. Returns the modifier when its double
    /// tap completes.
    public mutating func handle(_ input: Input) -> TapModifier? {
        switch input {
        case .otherInput:
            cancel(blockUntilReleased: pressed != nil)
            return nil

        case .modifiers(let held, let time):
            if held.isEmpty {
                defer { blockedUntilAllReleased = false }
                guard !blockedUntilAllReleased, let press = pressed else { return nil }
                pressed = nil
                guard time - press.at <= maxPressDuration else {
                    firstTap = nil
                    return nil
                }
                if let first = firstTap, first.modifier == press.modifier {
                    firstTap = nil
                    return press.modifier
                }
                firstTap = (press.modifier, time)
                return nil
            }

            guard !blockedUntilAllReleased else { return nil }
            guard held.count == 1, let modifier = held.first else {
                cancel(blockUntilReleased: true)  // two modifiers: a combo, not a tap
                return nil
            }
            if let first = firstTap, first.modifier != modifier || time - first.releasedAt > maxGap {
                firstTap = nil
            }
            pressed = (modifier, time)
            return nil
        }
    }

    private mutating func cancel(blockUntilReleased: Bool) {
        pressed = nil
        firstTap = nil
        if blockUntilReleased { blockedUntilAllReleased = true }
    }
}
