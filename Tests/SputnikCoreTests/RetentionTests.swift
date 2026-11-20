import Foundation
import Testing
@testable import SputnikCore

@Suite("Retention policy")
struct RetentionPolicyTests {
    let policy = RetentionPolicy(maxUnpinned: 500, maxAgeDays: 30)

    func item(_ id: Int64, ageDays: Double, pinned: Bool = false) -> ClipItem {
        ClipItem(
            id: id, kind: .text, text: "\(id)", contentHash: "\(id)", byteSize: 1,
            createdAt: daysAgo(ageDays), lastUsedAt: daysAgo(ageDays), isPinned: pinned
        )
    }

    @Test("Keeps the newest 500 unpinned items")
    func keepsNewest500() {
        // ids 1...502; higher id = newer (ages spread inside one day).
        let items = (1...502).map { item(Int64($0), ageDays: 1 - Double($0) / 1000) }
        #expect(Set(policy.expiredIDs(in: items, now: referenceNow)) == [1, 2])
    }

    @Test("Pinned items don't count toward the 500 limit")
    func pinnedDontCount() {
        var items = (1...500).map { item(Int64($0), ageDays: 1) }
        items += (501...520).map { item(Int64($0), ageDays: 2, pinned: true) }
        #expect(policy.expiredIDs(in: items, now: referenceNow).isEmpty)
    }

    @Test("Unpinned items older than 30 days expire; exactly 30 days is kept")
    func ageLimit() {
        let items = [item(1, ageDays: 29), item(2, ageDays: 30), item(3, ageDays: 30.01), item(4, ageDays: 400)]
        #expect(Set(policy.expiredIDs(in: items, now: referenceNow)) == [3, 4])
    }

    @Test("Pinned items never expire, however old (faked clock)")
    func pinnedNeverExpire() {
        let items = [item(1, ageDays: 31, pinned: true), item(2, ageDays: 3_650, pinned: true), item(3, ageDays: 31)]
        #expect(policy.expiredIDs(in: items, now: referenceNow) == [3])
    }
}

@Suite("Retention in the database")
struct RetentionDatabaseTests {
    let history: TemporaryHistory
    var db: HistoryDatabase { history.database }

    init() throws {
        history = try TemporaryHistory()
    }

    @Test("Ingesting sweeps expired items and deletes their blob files")
    func sweepRemovesRowsAndBlobs() throws {
        let policy = RetentionPolicy(maxUnpinned: 500, maxAgeDays: 30)
        let old = try db.ingest(pngClip(seed: 1, at: daysAgo(31)), retention: policy)
        #expect(try history.blobFiles().count == 1)

        let change = try db.ingest(textClip("fresh"), retention: policy)

        #expect(change.removedIDs == [old.item.id!])
        #expect(try db.allItems().map(\.text) == ["fresh"])
        #expect(try history.blobFiles().isEmpty)
    }

    @Test("The count limit applies on ingest")
    func countLimitOnIngest() throws {
        let policy = RetentionPolicy(maxUnpinned: 3, maxAgeDays: 30)
        for i in 1...5 {
            _ = try db.ingest(textClip("item \(i)", at: daysAgo(Double(10 - i))), retention: policy)
        }
        #expect(try db.allItems().map(\.text) == ["item 5", "item 4", "item 3"])
    }

    @Test("History survives reopening the database file")
    func persistsAcrossReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ClipDockTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try HistoryDatabase(directory: dir).ingest(textClip("kept"), retention: RetentionPolicy())
        let reopened = try HistoryDatabase(directory: dir)
        #expect(try reopened.allItems().map(\.text) == ["kept"])
    }
}
