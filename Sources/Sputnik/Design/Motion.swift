import AppKit
import SwiftUI

/// Motion values from section 5.2. `interpolatingSpring(mass:stiffness:damping:)` uses the
/// same physics as the Motion library, so the reference values carry over 1:1.
/// With Reduce Motion on, movement happens instantly and fades take 120 ms.
enum Motion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Tooltip slide (x), and the selected-row capsule.
    static func slide(_ reduce: Bool) -> Animation? {
        reduce ? nil : .interpolatingSpring(mass: 0.7, stiffness: 650, damping: 44)
    }

    /// Tooltip reveal and clip width, with no overshoot.
    static func reveal(_ reduce: Bool) -> Animation? {
        reduce ? nil : .interpolatingSpring(mass: 0.7, stiffness: 720, damping: 52)
    }

    /// Dock collapse and expand width.
    static func collapse(_ reduce: Bool) -> Animation? {
        reduce ? nil : .interpolatingSpring(mass: 0.9, stiffness: 460, damping: 42)
    }

    /// Opacity changes: 180 ms ease-out-expo, or 120 ms with Reduce Motion.
    static func fade(_ reduce: Bool) -> Animation {
        reduce ? .easeInOut(duration: 0.12) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
    }
}
