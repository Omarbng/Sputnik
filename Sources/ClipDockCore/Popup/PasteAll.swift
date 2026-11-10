/// What goes between items in "paste all" (⌘↩).
public enum PasteAllSeparator: String, CaseIterable, Sendable {
    case newline
    case space
    case comma
    case nothing

    public var string: String {
        switch self {
        case .newline: "\n"
        case .space: " "
        case .comma: ", "
        case .nothing: ""
        }
    }

    public var label: String {
        switch self {
        case .newline: "New line"
        case .space: "Space"
        case .comma: "Comma"
        case .nothing: "Nothing"
        }
    }
}

public enum PasteAll {
    /// Joins the items' text in the given order. Images have no text and are left out;
    /// `skipped` counts them.
    public static func join(_ items: [ClipItem], separator: PasteAllSeparator) -> (text: String, skipped: Int) {
        let texts = items.compactMap { item -> String? in
            item.kind == .image ? nil : item.text
        }
        return (texts.joined(separator: separator.string), items.count - texts.count)
    }
}
