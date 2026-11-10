import Foundation
import Testing
@testable import ClipDockCore

@Suite("Dedupe")
struct DedupeTests {
    let history: TemporaryHistory
    var db: HistoryDatabase { history.database }
    let policy = RetentionPolicy()

    init() throws {
        history = try TemporaryHistory()
    }

    @Test("Copying the same text again keeps one item and moves it to the top")
    func sameTextMovesToTop() throws {
        let first = try db.ingest(textClip("hello", at: daysAgo(3)), retention: policy)
        _ = try db.ingest(textClip("other", at: daysAgo(2)), retention: policy)
        let again = try db.ingest(textClip("hello", at: daysAgo(1), app: "com.google.Chrome"), retention: policy)

        #expect(again.wasDuplicate)
        #expect(again.item.id == first.item.id)
        let items = try db.allItems()
        #expect(items.map(\.text) == ["hello", "other"])
        #expect(items[0].lastUsedAt == daysAgo(1))
        #expect(items[0].createdAt == daysAgo(3))
        #expect(items[0].sourceBundleID == "com.google.Chrome")
    }

    @Test("Different text adds separate items")
    func differentTextAdds() throws {
        _ = try db.ingest(textClip("a", at: daysAgo(2)), retention: policy)
        let b = try db.ingest(textClip("b", at: daysAgo(1)), retention: policy)
        #expect(!b.wasDuplicate)
        #expect(try db.allItems().count == 2)
    }

    @Test("Dedupe is exact: case and whitespace matter")
    func exactMatchOnly() throws {
        _ = try db.ingest(textClip("Hello"), retention: policy)
        _ = try db.ingest(textClip("hello"), retention: policy)
        _ = try db.ingest(textClip("hello "), retention: policy)
        #expect(try db.allItems().count == 3)
    }

    @Test("The same image twice is one item and one blob file")
    func sameImageOneBlob() throws {
        _ = try db.ingest(pngClip(seed: 7, at: daysAgo(2)), retention: policy)
        let again = try db.ingest(pngClip(seed: 7, at: daysAgo(1)), retention: policy)
        #expect(again.wasDuplicate)
        #expect(try db.allItems().count == 1)
        #expect(try history.blobFiles().count == 1)
    }

    @Test("A URL and text with the same string are different kinds, so both are kept")
    func kindIsPartOfIdentity() throws {
        let url = CapturedClip(payload: .url("https://example.com"), sourceBundleID: nil, sourceAppName: nil, capturedAt: referenceNow)
        _ = try db.ingest(url, retention: policy)
        _ = try db.ingest(textClip("https://example.com"), retention: policy)
        #expect(try db.allItems().count == 2)
    }

    @Test("Translations are stored with the translated badge, and a re-copy keeps it")
    func translationBadge() throws {
        var clip = textClip("Доброе утро", at: daysAgo(2))
        clip.isTranslation = true
        let stored = try db.ingest(clip, retention: policy)
        #expect(stored.item.isTranslation)

        let recopied = try db.ingest(textClip("Доброе утро", at: daysAgo(1)), retention: policy)
        #expect(recopied.wasDuplicate)
        #expect(recopied.item.isTranslation)
        #expect(try db.allItems().first?.isTranslation == true)
    }

    @Test("A lone web URL is classified as a URL; other text stays text")
    func urlClassification() {
        #expect(ClipPayload.fromText("  https://example.com/a?b=1\n", rtf: nil) == .url("https://example.com/a?b=1"))
        #expect(ClipPayload.fromText("see https://example.com", rtf: nil) == .text("see https://example.com", rtf: nil))
        #expect(ClipPayload.fromText("example.com", rtf: nil) == .text("example.com", rtf: nil))
    }
}
