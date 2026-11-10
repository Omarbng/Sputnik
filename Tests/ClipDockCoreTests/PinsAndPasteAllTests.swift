import Foundation
import Testing
@testable import ClipDockCore

@Suite("Pins and Clear history")
struct PinsTests {
    let history: TemporaryHistory
    var db: HistoryDatabase { history.database }
    let policy = RetentionPolicy(maxUnpinned: 500, maxAgeDays: 30)

    init() throws {
        history = try TemporaryHistory()
    }

    @Test("A pinned item survives the 30-day retention (faked clock)")
    func pinnedSurvivesRetention() throws {
        let pinned = try db.ingest(textClip("pin me", at: daysAgo(40)), retention: policy)
        _ = try db.ingest(textClip("forget me", at: daysAgo(40)), retention: policy)
        _ = try db.setPinned(true, id: pinned.item.id!)

        let removed = try db.applyRetention(policy, now: referenceNow)

        #expect(removed.count == 1)
        #expect(try db.allItems().map(\.text) == ["pin me"])
    }

    @Test("Unpinning an old item lets retention remove it")
    func unpinThenExpire() throws {
        let item = try db.ingest(textClip("old", at: daysAgo(40)), retention: policy)
        _ = try db.setPinned(true, id: item.item.id!)
        _ = try db.applyRetention(policy, now: referenceNow)
        #expect(try db.allItems().count == 1)

        let unpinned = try db.setPinned(false, id: item.item.id!)
        #expect(unpinned?.isPinned == false)
        _ = try db.applyRetention(policy, now: referenceNow)
        #expect(try db.allItems().isEmpty)
    }

    @Test("Clear history keeps pinned items and their blobs, and deletes the rest")
    func clearKeepsPinned() throws {
        let pinnedImage = try db.ingest(pngClip(seed: 1), retention: policy)
        _ = try db.setPinned(true, id: pinnedImage.item.id!)
        _ = try db.ingest(pngClip(seed: 2), retention: policy)
        _ = try db.ingest(textClip("bye"), retention: policy)
        #expect(try history.blobFiles().count == 2)

        let removed = try db.clearUnpinned()

        #expect(removed.count == 2)
        #expect(try db.allItems().map(\.id) == [pinnedImage.item.id])
        #expect(try history.blobFiles() == [pinnedImage.item.imageBlob!])
    }

    @Test("Pinned items don't count toward the 500-item limit in the database")
    func pinnedOutsideLimit() throws {
        let small = RetentionPolicy(maxUnpinned: 2, maxAgeDays: 30)
        let first = try db.ingest(textClip("first", at: daysAgo(5)), retention: small)
        _ = try db.setPinned(true, id: first.item.id!)
        for i in 1...4 { _ = try db.ingest(textClip("n\(i)", at: daysAgo(Double(4 - i))), retention: small) }
        #expect(Set(try db.allItems().compactMap(\.text)) == ["first", "n4", "n3"])
    }
}

@Suite("Multi-select and paste all")
struct PasteAllTests {
    func item(_ id: Int64, _ text: String?, kind: ClipKind = .text) -> ClipItem {
        ClipItem(id: id, kind: kind, text: text, contentHash: "\(id)", byteSize: 1, createdAt: referenceNow, lastUsedAt: referenceNow)
    }

    @Test("Marks keep the order they were added and renumber when one is removed")
    func markOrder() {
        var marks = MarkedSelection()
        marks.toggle(30); marks.toggle(10); marks.toggle(20)
        #expect(marks.ids == [30, 10, 20])
        #expect(marks.number(for: 10) == 2)
        marks.toggle(10)
        #expect(marks.ids == [30, 20])
        #expect(marks.number(for: 20) == 2)
        #expect(marks.number(for: 10) == nil)
    }

    @Test("Marks forget deleted items")
    func keepOnly() {
        var marks = MarkedSelection()
        [1, 2, 3].forEach { marks.toggle($0) }
        marks.keep(only: [1, 3])
        #expect(marks.ids == [1, 3])
    }

    @Test("Three items join in the marked order with each separator", arguments: PasteAllSeparator.allCases)
    func join(separator: PasteAllSeparator) {
        let items = [item(3, "third"), item(1, "first"), item(2, "second")]
        let expected = ["third", "first", "second"].joined(separator: separator.string)
        #expect(PasteAll.join(items, separator: separator).text == expected)
    }

    @Test("Separators are newline, space, comma, nothing")
    func separatorStrings() {
        #expect(PasteAllSeparator.newline.string == "\n")
        #expect(PasteAllSeparator.space.string == " ")
        #expect(PasteAllSeparator.comma.string == ", ")
        #expect(PasteAllSeparator.nothing.string == "")
    }

    @Test("Images are left out and counted; URLs and file paths are kept")
    func imagesSkipped() {
        let items = [item(1, "a"), item(2, nil, kind: .image), item(3, "https://x.com", kind: .url), item(4, "/tmp/f.txt", kind: .file)]
        let result = PasteAll.join(items, separator: .space)
        #expect(result.text == "a https://x.com /tmp/f.txt")
        #expect(result.skipped == 1)
    }
}
