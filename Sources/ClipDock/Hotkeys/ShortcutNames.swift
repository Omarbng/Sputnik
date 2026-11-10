@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌘⇧V. Chrome and Google Docs use ⌘⇧V for "paste as plain text"; this takes it over.
    static let openPopup = Self("openPopup", default: .init(.v, modifiers: [.command, .shift]))
}
