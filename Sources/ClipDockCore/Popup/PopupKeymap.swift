/// What a key press inside the popup does.
public enum PopupCommand: Equatable, Sendable {
    case close
    case moveUp
    case moveDown
    case pasteSelected
    /// ⌘1–⌘9: paste the Nth visible item (1-based).
    case pasteNumber(Int)
    case copySelected
    case deleteSelected
    /// ⌘T: translate the selected item and show the result under it.
    case translateSelected
    // Editing in the search field. A menu-bar app has no Edit menu to supply these.
    case selectAllText
    case cutText
    case pasteText
}

/// Maps key presses to popup commands by **virtual key code**, not character, so the same
/// keys work with any keyboard layout (for example, Russian).
public enum PopupKeymap {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    // Carbon kVK_* values (HIToolbox/Events.h).
    static let escape: UInt16 = 0x35
    static let returnKey: UInt16 = 0x24
    static let keypadEnter: UInt16 = 0x4C
    static let upArrow: UInt16 = 0x7E
    static let downArrow: UInt16 = 0x7D
    static let delete: UInt16 = 0x33
    static let a: UInt16 = 0x00
    static let c: UInt16 = 0x08
    static let v: UInt16 = 0x09
    static let x: UInt16 = 0x07
    static let t: UInt16 = 0x11
    static let digits: [UInt16: Int] = [
        0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4, 0x17: 5, 0x16: 6, 0x1A: 7, 0x1C: 8, 0x19: 9,
    ]

    /// Returns nil for keys the search field should handle (typing, ←/→, ⌫ …).
    public static func command(keyCode: UInt16, modifiers: Modifiers) -> PopupCommand? {
        if modifiers.isEmpty {
            switch keyCode {
            case escape: return .close
            case returnKey, keypadEnter: return .pasteSelected
            case upArrow: return .moveUp
            case downArrow: return .moveDown
            default: return nil
            }
        }
        if modifiers == .command {
            if let number = digits[keyCode] { return .pasteNumber(number) }
            switch keyCode {
            case c: return .copySelected
            case delete: return .deleteSelected
            case t: return .translateSelected
            case a: return .selectAllText
            case x: return .cutText
            case v: return .pasteText
            default: return nil
            }
        }
        return nil
    }
}
