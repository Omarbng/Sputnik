import Testing
@testable import ClipDockCore

@Suite("Search")
struct HistoryFilterTests {
    func item(_ id: Int64, _ text: String?, kind: ClipKind = .text, app: String? = nil, pinned: Bool = false) -> ClipItem {
        ClipItem(
            id: id, kind: kind, text: text, contentHash: "\(id)", sourceAppName: app, byteSize: 1,
            createdAt: referenceNow, lastUsedAt: referenceNow, isPinned: pinned
        )
    }

    var items: [ClipItem] {
        [
            item(1, "Hello World", app: "Safari"),
            item(2, "Привет, мир", app: "Telegram"),
            item(3, "quarterly report.pdf", kind: .file, app: "Finder", pinned: true),
            item(4, nil, kind: .image, app: "Preview"),
        ]
    }

    func ids(_ query: String) -> [Int64] {
        HistoryFilter.sections(of: items, query: query).all.compactMap(\.id)
    }

    @Test("An empty or blank query shows everything, pinned first")
    func emptyQuery() {
        #expect(ids("") == [3, 1, 2, 4])
        #expect(ids("   ") == [3, 1, 2, 4])
    }

    @Test("Matching ignores case, including Cyrillic")
    func caseInsensitive() {
        #expect(ids("hello") == [1])
        #expect(ids("WORLD") == [1])
        #expect(ids("ПРИВЕТ") == [2])
    }

    @Test("The source app name is searched too")
    func appName() {
        #expect(ids("safari") == [1])
        #expect(ids("telegram") == [2])
    }

    @Test("Every word must match")
    func allWords() {
        #expect(ids("hello safari") == [1])
        #expect(ids("hello telegram").isEmpty)
    }

    @Test("Images match the word \"image\"")
    func images() {
        #expect(ids("image") == [4])
    }

    @Test("Precomputed keys are used when given")
    func usesKeys() {
        let sections = HistoryFilter.sections(of: items, query: "zebra", keys: [2: "zebra"])
        #expect(sections.all.compactMap(\.id) == [2])
    }

    @Test("Only the first 2,000 characters of long text are searched")
    func longText() {
        let long = String(repeating: "a", count: 3_000) + "needle"
        #expect(HistoryFilter.sections(of: [item(9, long)], query: "needle").all.isEmpty)
    }

    @Test("Row titles use the first non-empty line")
    func title() {
        #expect(item(1, "\n\n  first line  \nsecond").title == "first line")
        #expect(item(2, "/Users/o/a.txt\n/Users/o/b.png", kind: .file).title == "a.txt, b.png")
        #expect(item(3, nil, kind: .image).title == "Image")
    }
}
