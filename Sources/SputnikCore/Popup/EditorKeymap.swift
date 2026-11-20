/// What a key does while the popup's editor is open (⌘E, ⌘N). Everything else goes to the
/// text fields, so ↩, Space, and the arrows type and move as usual.
public enum EditorCommand: Equatable, Sendable {
    /// Esc: back to the list, without saving.
    case cancel
    /// ⌘S
    case save
    /// ⌘↩: paste the edited text, or save a new item.
    case primary
    /// ⌘L: turn Secret on or off for a new item.
    case toggleSecret
    // Text editing. A menu-bar app has no Edit menu to supply these.
    case selectAll
    case cut
    case copy
    case paste
    case undo
    case redo
}

public enum EditorKeymap {
    public static func command(keyCode: UInt16, modifiers: PopupKeymap.Modifiers) -> EditorCommand? {
        typealias K = PopupKeymap
        if modifiers.isEmpty, keyCode == K.escape { return .cancel }
        if modifiers == [.command, .shift], keyCode == K.z { return .redo }
        guard modifiers == .command else { return nil }
        switch keyCode {
        case K.s: return .save
        case K.returnKey, K.keypadEnter: return .primary
        case K.l: return .toggleSecret
        case K.a: return .selectAll
        case K.x: return .cut
        case K.c: return .copy
        case K.v: return .paste
        case K.z: return .undo
        default: return nil
        }
    }
}
