@preconcurrency import KeyboardShortcuts

/// Optional key combinations, set in Settings. The main shortcuts are double-taps
/// (see `DoubleTapMonitor`); these have no default.
extension KeyboardShortcuts.Name {
    static let openPopup = Self("openPopup")
    static let translate = Self("translate")
}
