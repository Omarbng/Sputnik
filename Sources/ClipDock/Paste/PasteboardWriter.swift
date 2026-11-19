import AppKit
import ClipDockCore

/// Writes to the general pasteboard, always adding ClipDock's private marker type so capture
/// ignores our own writes.
@MainActor
enum PasteboardWriter {
    static let internalType = NSPasteboard.PasteboardType(SkipRules.internalType)
    /// nspasteboard.org's marker for passwords. Clipboard managers, ClipDock included, skip it.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Writes a history item with its original formats (RTF, PNG, file URLs).
    @discardableResult
    static func write(_ item: ClipItem, blobs: BlobStore, to pasteboard: NSPasteboard = .general) -> Bool {
        let items = pasteboardItems(for: item, blobs: blobs)
        guard !items.isEmpty else { return false }
        return write(items, to: pasteboard)
    }

    /// Writes plain text, such as a translation or joined "paste all" text.
    @discardableResult
    static func write(text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        return write([item], to: pasteboard)
    }

    /// Writes a secret's value, marked concealed so clipboard managers don't keep it.
    @discardableResult
    static func write(secret: String, to pasteboard: NSPasteboard = .general) -> Bool {
        let item = NSPasteboardItem()
        item.setString(secret, forType: .string)
        item.setData(Data(), forType: concealedType)
        return write([item], to: pasteboard)
    }

    /// Writes prepared items (several types at once, such as JPEG plus a file).
    @discardableResult
    static func write(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard = .general) -> Bool {
        for item in items {
            item.setData(Data(), forType: internalType)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    private static func pasteboardItems(for item: ClipItem, blobs: BlobStore) -> [NSPasteboardItem] {
        switch item.kind {
        case .text:
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.text ?? "", forType: .string)
            if let name = item.rtfBlob, let rtf = try? Data(contentsOf: blobs.url(for: name)) {
                pbItem.setData(rtf, forType: .rtf)
            }
            return [pbItem]
        case .url:
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.text ?? "", forType: .string)
            pbItem.setString(item.text ?? "", forType: .URL)
            return [pbItem]
        case .image:
            guard let name = item.imageBlob, let png = try? Data(contentsOf: blobs.url(for: name)) else { return [] }
            let pbItem = NSPasteboardItem()
            pbItem.setData(png, forType: .png)
            return [pbItem]
        case .file:
            return (item.text ?? "").split(separator: "\n").map { path in
                let pbItem = NSPasteboardItem()
                pbItem.setString(URL(fileURLWithPath: String(path)).absoluteString, forType: .fileURL)
                return pbItem
            }
        case .secret:
            return []  // a secret's value is only ever written by SecretActions, after Touch ID
        }
    }
}
