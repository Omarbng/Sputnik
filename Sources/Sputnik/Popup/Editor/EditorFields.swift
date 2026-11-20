import AppKit

/// The editor's text fields. They're AppKit views made once with the panel, like the search
/// field, so the controller can focus them reliably; SwiftUI only places them.
@MainActor
final class EditorFields: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    let nameField = NSTextField.editorField(placeholder: "Name (optional)", secure: false)
    let secretField = NSTextField.editorField(placeholder: "Type or paste the secret", secure: true)
    let textScroll = NSScrollView()
    let textView = EditorTextView()

    /// ↩ in the secret field saves.
    var onSubmitSecret: (() -> Void)?

    override init() {
        super.init()
        nameField.delegate = self
        secretField.delegate = self
        // A secure field doesn't pass ↩ to its delegate, so ↩ there uses the field's action.
        secretField.target = self
        secretField.action = #selector(secretSubmitted)
        secretField.cell?.sendsActionOnEndEditing = false  // only ↩, never ⇥ or a click away
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.scrollerStyle = .overlay
        textScroll.borderType = .noBorder
        let text = textView
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        textScroll.documentView = text
        text.delegate = self
        text.isRichText = false
        text.allowsUndo = true
        text.drawsBackground = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.insertionPointColor = .labelColor
        text.textContainerInset = NSSize(width: 4, height: 6)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
    }

    var name: String { nameField.stringValue }
    var text: String { textView.string }
    var secret: String { secretField.stringValue }

    func load(name: String?, text: String, namePlaceholder: String) {
        nameField.stringValue = name ?? ""
        nameField.placeholderAttributedString = NSAttributedString.placeholder(namePlaceholder)
        textView.string = text
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.scrollToBeginningOfDocument(nil)
        secretField.stringValue = ""
    }

    /// Wipes everything, so a typed secret doesn't stay in memory after the editor closes.
    func clear() {
        load(name: nil, text: "", namePlaceholder: "Name (optional)")
    }

    // MARK: Delegates

    /// ↩ in the name field moves on to the value; ⇥ and ⇧⇥ go back and forth.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let window = control.window
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard control === nameField else { return false }  // the secret field's action saves
            focusValue(in: window)
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            if control === nameField { focusValue(in: window) } else { focus(nameField, in: window) }
            return true
        default:
            return false
        }
    }

    /// ⇥ in the text goes to the name field when there is one; otherwise it types a tab.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)),
              nameField.window != nil
        else { return false }
        focus(nameField, in: textView.window)
        return true
    }

    @objc private func secretSubmitted() {
        onSubmitSecret?()
    }

    private func focusValue(in window: NSWindow?) {
        focus(secretField.window != nil ? secretField : textView, in: window)
    }

    private func focus(_ view: NSView, in window: NSWindow?) {
        window?.makeFirstResponder(view)
    }
}

/// The editor's text view.
final class EditorTextView: NSTextView {}

extension NSTextField {
    /// A single-line field for the editor: borderless and transparent (SwiftUI draws the frame).
    static func editorField(placeholder: String, secure: Bool) -> NSTextField {
        let field = secure ? NSSecureTextField() : NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.placeholderAttributedString = .placeholder(placeholder)
        return field
    }
}

extension NSAttributedString {
    static func placeholder(_ text: String, size: CGFloat = 13) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: size),
        ])
    }
}
