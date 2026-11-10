@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌘⇧V. Chrome and Google Docs use ⌘⇧V for "paste as plain text"; this takes it over.
    static let openPopup = Self("openPopup", default: .init(.v, modifiers: [.command, .shift]))
    /// ⌥⌘T: replace the selected text with its translation.
    static let translateInPlace = Self("translateInPlace", default: .init(.t, modifiers: [.command, .option]))
    /// ⇧⌥⌘T: show the translation of the selected text without replacing anything.
    static let translateShowOnly = Self("translateShowOnly", default: .init(.t, modifiers: [.command, .option, .shift]))
}
