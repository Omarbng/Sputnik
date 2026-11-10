import Foundation
import GRDB

/// Result of storing one capture, so the in-memory list can mirror the database.
public struct HistoryChange: Sendable, Equatable {
    public var item: ClipItem
    public var wasDuplicate: Bool
    public var removedIDs: [Int64]
}

/// SQLite history (GRDB) plus the blob folder. Thread-safe; call it off the main thread.
public final class HistoryDatabase: Sendable {
    private let queue: DatabaseQueue
    public let blobs: BlobStore

    /// Opens or creates `<directory>/history.sqlite` and `<directory>/blobs/`.
    public convenience init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "history.sqlite").path(percentEncoded: false)
        try self.init(
            queue: DatabaseQueue(path: path),
            blobs: BlobStore(directory: directory.appending(path: "blobs", directoryHint: .isDirectory))
        )
    }

    /// In-memory database with blobs in `blobDirectory`. For tests.
    public static func inMemory(blobDirectory: URL) throws -> HistoryDatabase {
        try HistoryDatabase(queue: DatabaseQueue(), blobs: BlobStore(directory: blobDirectory))
    }

    init(queue: DatabaseQueue, blobs: BlobStore) throws {
        self.queue = queue
        self.blobs = blobs
        try Self.migrator.migrate(queue)
    }

    /// All items, most recently used first.
    public func allItems() throws -> [ClipItem] {
        try queue.read { db in
            try ClipItem.order(ClipItem.Columns.lastUsedAt.desc).fetchAll(db)
        }
    }

    /// Stores a capture. If identical content exists, that item moves to the top instead.
    /// Then applies `retention`.
    public func ingest(_ clip: CapturedClip, retention: RetentionPolicy) throws -> HistoryChange {
        let now = clip.capturedAt
        let hash = clip.contentHash
        // Blobs are named by their hash, so writing before the transaction is idempotent.
        let imageBlob = try clip.imageData.map { try blobs.store($0, fileExtension: "png") }
        let rtfBlob = try clip.rtf.map { try blobs.store($0, fileExtension: "rtf") }

        let (change, orphans) = try queue.write { db -> (HistoryChange, [String]) in
            let item: ClipItem
            let wasDuplicate: Bool
            if var existing = try ClipItem.filter(ClipItem.Columns.contentHash == hash).fetchOne(db) {
                existing.lastUsedAt = now
                existing.sourceBundleID = clip.sourceBundleID ?? existing.sourceBundleID
                existing.sourceAppName = clip.sourceAppName ?? existing.sourceAppName
                try existing.update(db)
                item = existing
                wasDuplicate = true
            } else {
                var new = ClipItem(
                    kind: clip.kind,
                    text: clip.storedText,
                    rtfBlob: rtfBlob,
                    imageBlob: imageBlob,
                    contentHash: hash,
                    sourceBundleID: clip.sourceBundleID,
                    sourceAppName: clip.sourceAppName,
                    byteSize: clip.byteSize,
                    createdAt: now,
                    lastUsedAt: now
                )
                try new.insert(db)
                item = new
                wasDuplicate = false
            }
            let swept = try Self.sweep(retention, now: now, in: db)
            let change = HistoryChange(item: item, wasDuplicate: wasDuplicate, removedIDs: swept.removedIDs)
            return (change, swept.orphanBlobs)
        }
        orphans.forEach(blobs.remove)
        return change
    }

    /// Deletes expired items and their unreferenced blobs. Returns the removed IDs.
    @discardableResult
    public func applyRetention(_ policy: RetentionPolicy, now: Date) throws -> [Int64] {
        let swept = try queue.write { db in try Self.sweep(policy, now: now, in: db) }
        swept.orphanBlobs.forEach(blobs.remove)
        return swept.removedIDs
    }

    /// Marks an item as just used (pasted or copied from history), which moves it to the top.
    public func touch(id: Int64, now: Date) throws -> ClipItem? {
        try queue.write { db in
            guard var item = try ClipItem.fetchOne(db, key: id) else { return nil }
            item.lastUsedAt = now
            try item.update(db)
            return item
        }
    }

    /// Deletes items and any blob files nothing else references. Returns the deleted IDs.
    @discardableResult
    public func delete(ids: [Int64]) throws -> [Int64] {
        let result = try queue.write { db in try Self.deleteRows(ids, in: db) }
        result.orphanBlobs.forEach(blobs.remove)
        return result.removedIDs
    }

    // MARK: - Private

    private typealias Deletion = (removedIDs: [Int64], orphanBlobs: [String])

    private static func sweep(_ policy: RetentionPolicy, now: Date, in db: Database) throws -> Deletion {
        let ids = policy.expiredIDs(in: try ClipItem.fetchAll(db), now: now)
        return try deleteRows(ids, in: db)
    }

    private static func deleteRows(_ ids: [Int64], in db: Database) throws -> Deletion {
        guard !ids.isEmpty else { return ([], []) }
        let doomed = try ClipItem.fetchAll(db, keys: ids)
        let blobNames = Set(doomed.flatMap { [$0.imageBlob, $0.rtfBlob].compactMap { $0 } })
        _ = try ClipItem.deleteAll(db, keys: ids)
        let orphans = try blobNames.filter { name in
            try ClipItem
                .filter(ClipItem.Columns.imageBlob == name || ClipItem.Columns.rtfBlob == name)
                .fetchCount(db) == 0
        }
        return (doomed.compactMap(\.id), Array(orphans))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: ClipItem.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("text", .text)
                t.column("rtfBlob", .text)
                t.column("imageBlob", .text)
                t.column("contentHash", .text).notNull().unique()
                t.column("sourceBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("byteSize", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull().indexed()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }
}
