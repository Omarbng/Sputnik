import Foundation
import GRDB

/// Saved items: text Omar types in (⌘N), secrets, and edits (⌘E). Saved items are pinned, so
/// they never expire and survive "Clear history".
extension HistoryDatabase {
    public enum EditError: Error, Equatable {
        /// Another item already has exactly this text.
        case duplicate
        case notFound
    }

    /// Saves typed-in text. If the same text is already in history, that item is saved and
    /// named instead of adding a copy.
    public func saveText(_ text: String, name: String?, now: Date) throws -> ClipItem {
        let clip = CapturedClip(payload: .fromText(text, rtf: nil), sourceBundleID: nil, sourceAppName: nil, capturedAt: now)
        return try queue.write { db in
            if var existing = try ClipItem.filter(ClipItem.Columns.contentHash == clip.contentHash).fetchOne(db) {
                existing.isPinned = true
                existing.name = name ?? existing.name
                existing.lastUsedAt = now
                try existing.update(db)
                return existing
            }
            var item = ClipItem(
                kind: clip.kind, text: clip.storedText, contentHash: clip.contentHash,
                byteSize: clip.byteSize, createdAt: now, lastUsedAt: now, isPinned: true, name: name
            )
            try item.insert(db)
            return item
        }
    }

    /// Stores a secret's row: its name and Keychain reference only, never the value.
    public func saveSecret(name: String, secretRef: String, now: Date) throws -> ClipItem {
        try queue.write { db in
            var item = ClipItem(
                kind: .secret, text: nil, contentHash: "secret:" + secretRef,
                byteSize: 0, createdAt: now, lastUsedAt: now, isPinned: true,
                name: name, secretRef: secretRef
            )
            try item.insert(db)
            return item
        }
    }

    /// Saves an edit and moves the item to the top. `text` nil keeps the content (secrets, or
    /// a name-only change). New text drops the old formatting, since it no longer matches.
    public func edit(id: Int64, text: String?, name: String?, now: Date) throws -> ClipItem {
        let (item, orphans) = try queue.write { db -> (ClipItem, [String]) in
            guard var item = try ClipItem.fetchOne(db, key: id) else { throw EditError.notFound }
            var dropped: Set<String> = []
            if let text, item.kind == .text || item.kind == .url, text != item.text {
                let clip = CapturedClip(payload: .fromText(text, rtf: nil), sourceBundleID: nil, sourceAppName: nil, capturedAt: now)
                let clash = try ClipItem
                    .filter(ClipItem.Columns.contentHash == clip.contentHash && ClipItem.Columns.id != id)
                    .fetchCount(db)
                guard clash == 0 else { throw EditError.duplicate }
                if let rtf = item.rtfBlob { dropped.insert(rtf) }
                item.kind = clip.kind
                item.text = clip.storedText
                item.rtfBlob = nil
                item.contentHash = clip.contentHash
                item.byteSize = clip.byteSize
            }
            item.name = name
            item.lastUsedAt = now
            try item.update(db)
            return (item, try Self.unreferenced(dropped, in: db))
        }
        orphans.forEach(blobs.remove)
        return item
    }
}
