/// What the actions menu (⌘K, a right-click, or a row's ⋯ button) offers for one item.
public enum ClipAction: String, CaseIterable, Sendable {
    case paste
    /// ⌥↩: text without its formatting, or a file's path.
    case pastePlain
    case copy
    /// ⌘E: change the text (or a secret's name and value) before pasting or saving it.
    case edit
    case translate
    /// ⌘O: open a link in the browser, or show a file in Finder.
    case open
    /// ⌘P: add to Saved, or take it out.
    case togglePin
    case uppercase
    case lowercase
    case tidy
    case delete

    /// In menu order. Secrets are always saved, and their value never leaves the Keychain except
    /// to be pasted or copied.
    public static func available(for item: ClipItem) -> [ClipAction] {
        switch item.kind {
        case .secret:
            [.paste, .copy, .edit, .delete]
        case .image:
            [.paste, .copy, .togglePin, .delete]
        case .file:
            [.paste, .pastePlain, .copy, .open, .togglePin, .delete]
        case .url:
            [.paste, .copy, .open, .edit, .togglePin, .delete]
        case .text:
            (item.rtfBlob != nil ? [.paste, .pastePlain] : [.paste])
                + [.copy, .edit, .translate, .togglePin, .uppercase, .lowercase, .tidy, .delete]
        }
    }

    public func title(for item: ClipItem) -> String {
        switch self {
        case .paste: "Paste"
        case .pastePlain: item.kind == .file ? "Paste as Path" : "Paste as Plain Text"
        case .copy: "Copy"
        case .edit: "Edit…"
        case .translate: "Translate"
        case .open: item.kind == .file ? "Show in Finder" : "Open Link"
        case .togglePin: item.isPinned ? "Remove from Saved" : "Add to Saved"
        case .uppercase: "Paste in UPPERCASE"
        case .lowercase: "Paste in lowercase"
        case .tidy: "Paste without Extra Spaces"
        case .delete: "Delete"
        }
    }

    /// Keycaps shown next to the title. The clean-up actions have no shortcut.
    public var keys: [String] {
        switch self {
        case .paste: ["↩"]
        case .pastePlain: ["⌥", "↩"]
        case .copy: ["⌘", "C"]
        case .edit: ["⌘", "E"]
        case .translate: ["⌘", "T"]
        case .open: ["⌘", "O"]
        case .togglePin: ["⌘", "P"]
        case .delete: ["⌘", "⌫"]
        case .uppercase, .lowercase, .tidy: []
        }
    }

    /// A divider goes above these, to group the menu.
    public var startsGroup: Bool {
        self == .uppercase || self == .delete
    }
}
