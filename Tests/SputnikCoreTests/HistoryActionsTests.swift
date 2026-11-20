import Testing
@testable import SputnikCore

@Suite("Touch and delete")
struct HistoryActionsTests {
    let history: TemporaryHistory
    var db: HistoryDatabase { history.database }
    let policy = RetentionPolicy()

    init() throws {
        history = try TemporaryHistory()
    }

    @Test("Touching an item (paste from history) moves it to the top")
    func touchMovesToTop() throws {
        let old = try db.ingest(textClip("old", at: daysAgo(2)), retention: policy)
        _ = try db.ingest(textClip("new", at: daysAgo(1)), retention: policy)

        let touched = try db.touch(id: old.item.id!, now: referenceNow)

        #expect(touched?.lastUsedAt == referenceNow)
        #expect(try db.allItems().map(\.text) == ["old", "new"])
    }

    @Test("Touching a missing item returns nil")
    func touchMissing() throws {
        #expect(try db.touch(id: 999, now: referenceNow) == nil)
    }

    @Test("Deleting an image removes its row and its blob file")
    func deleteRemovesBlob() throws {
        let image = try db.ingest(pngClip(seed: 3), retention: policy)
        _ = try db.ingest(textClip("keep"), retention: policy)

        let removed = try db.delete(ids: [image.item.id!])

        #expect(removed == [image.item.id!])
        #expect(try db.allItems().map(\.text) == ["keep"])
        #expect(try history.blobFiles().isEmpty)
    }
}
