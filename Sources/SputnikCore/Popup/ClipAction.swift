import Foundation

/// What the actions menu (⌘K, a right-click, or a row's ⋯ button) offers for one item.
public enum ClipAction: String, CaseIterable, Sendable {
    case paste
    /// ⌥↩: text without its formatting, or a file's path.
    case pastePlain
    case copy
    /// ⌘E: change the text (or a secret's name and value) before pasting or saving it.
    case edit
    /// Text: translate it. Images: translate the text in the image.
    case translate
    /// ⇧Space / ⌘Y: see the whole text or the image.
    case peek
    /// ⌘O: open a link in the browser, or show a file in Finder.
    case open
    /// ⌘P: add to Saved, or take it out.
    case togglePin
    /// ⌘L: move it into the Keychain as a secret.
    case saveAsSecret
    // Apple Intelligence (on this Mac), shown under the row like a translation.
    case proofread
    case professional
    case shorter
    case summarize
    // Found in the text.
    case whatsApp
    case call
    case email
    case addToCalendar
    // Images.
    case copyText
    case pasteSmaller
    case copyAsJPEG
    case removeBackground
    // Clean-up.
    case uppercase
    case lowercase
    case tidy
    case delete

    /// What decides the menu besides the item itself.
    public struct Context: Sendable, Equatable {
        /// Apple Intelligence is available and the writing actions are on.
        public var writingTools: Bool

        public init(writingTools: Bool = false) {
            self.writingTools = writingTools
        }
    }

    /// In menu order. Secrets are always saved, and their value never leaves the Keychain except
    /// to be pasted or copied.
    public static func available(for item: ClipItem, context: Context = .init()) -> [ClipAction] {
        switch item.kind {
        case .secret:
            return [.paste, .copy, .edit, .delete]
        case .image:
            return [.paste, .copy, .peek, .copyText, .translate, .pasteSmaller, .copyAsJPEG, .removeBackground, .togglePin, .delete]
        case .file:
            let imageTools: [ClipAction] = item.imageFilePath != nil
                ? [.peek, .copyText, .translate, .pasteSmaller, .copyAsJPEG, .removeBackground]
                : []
            return [.paste, .pastePlain, .copy, .open] + imageTools + [.togglePin, .delete]
        case .url:
            return [.paste, .copy, .open, .edit, .peek, .togglePin, .saveAsSecret, .delete]
        case .text:
            var actions: [ClipAction] = item.rtfBlob != nil ? [.paste, .pastePlain] : [.paste]
            actions += [.copy, .edit, .translate, .peek, .togglePin, .saveAsSecret]
            // A number, address or date found in the text is the likely reason for opening the
            // menu, so those actions come before the writing ones.
            let found = ContactDetector.detect(in: item.text ?? "")
            if found.phone != nil { actions += [.whatsApp, .call] }
            if found.email != nil { actions.append(.email) }
            if found.date != nil { actions.append(.addToCalendar) }
            if context.writingTools { actions += RewriteStyle.menuStyles.map(\.action) }
            return actions + [.uppercase, .lowercase, .tidy, .delete]
        }
    }

    public func title(for item: ClipItem) -> String {
        let inImage = item.kind == .image || item.kind == .file
        return switch self {
        case .paste: "Paste"
        case .pastePlain: item.kind == .file ? "Paste as Path" : "Paste as Plain Text"
        case .copy: "Copy"
        case .edit: "Edit…"
        case .translate: inImage ? "Translate Text in Image" : "Translate"
        case .peek: "Quick Look"
        case .open: item.kind == .file ? "Show in Finder" : "Open Link"
        case .togglePin: item.isPinned ? "Remove from Saved" : "Add to Saved"
        case .saveAsSecret: "Save as Secret"
        case .proofread, .professional, .shorter, .summarize: rewriteStyle!.title
        case .whatsApp: "Message on WhatsApp"
        case .call: "Call"
        case .email: "Write Email"
        case .addToCalendar: "Add to Calendar…"
        case .copyText: "Copy Text in Image"
        case .pasteSmaller: "Paste Smaller Image"
        case .copyAsJPEG: "Copy as JPEG"
        case .removeBackground: "Remove Background"
        case .uppercase: "Paste in UPPERCASE"
        case .lowercase: "Paste in lowercase"
        case .tidy: "Paste without Extra Spaces"
        case .delete: "Delete"
        }
    }

    /// Keycaps shown next to the title. Most added actions have no shortcut.
    public var keys: [String] {
        switch self {
        case .paste: ["↩"]
        case .pastePlain: ["⌥", "↩"]
        case .copy: ["⌘", "C"]
        case .edit: ["⌘", "E"]
        case .translate: ["⌘", "T"]
        case .peek: ["⌘", "Y"]
        case .open: ["⌘", "O"]
        case .togglePin: ["⌘", "P"]
        case .saveAsSecret: ["⌘", "L"]
        case .delete: ["⌘", "⌫"]
        default: []
        }
    }

    /// Actions in the same group sit together; a divider separates groups.
    public var group: Int {
        switch self {
        case .paste, .pastePlain, .copy, .edit, .translate, .peek, .open, .togglePin, .saveAsSecret: 0
        case .whatsApp, .call, .email, .addToCalendar: 1
        case .proofread, .professional, .shorter, .summarize: 2
        case .copyText, .pasteSmaller, .copyAsJPEG, .removeBackground: 3
        case .uppercase, .lowercase, .tidy: 4
        case .delete: 5
        }
    }

    /// The Apple Intelligence style behind a writing action.
    public var rewriteStyle: RewriteStyle? {
        switch self {
        case .proofread: .proofread
        case .professional: .professional
        case .shorter: .shorter
        case .summarize: .summarize
        default: nil
        }
    }
}

extension RewriteStyle {
    /// The menu action for a style (menu styles only).
    public var action: ClipAction {
        switch self {
        case .proofread: .proofread
        case .professional: .professional
        case .shorter: .shorter
        default: .summarize
        }
    }
}

extension ClipItem {
    static let imageExtensions: Set<String> = ["heic", "heif", "png", "jpg", "jpeg", "tif", "tiff", "webp", "gif", "bmp"]

    /// For a single copied image file (a HEIC photo from Finder): its path.
    public var imageFilePath: String? {
        guard kind == .file, let text, !text.contains("\n") else { return nil }
        let ext = (text as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext) ? text : nil
    }
}
