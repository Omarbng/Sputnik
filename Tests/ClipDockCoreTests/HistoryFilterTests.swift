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

    func ids(_ query: String, scope: HistoryScope = .history) -> [Int64] {
        HistoryFilter.sections(of: items, query: query, scope: scope).all.compactMap(\.id)
    }

    @Test("History without a search shows only unsaved items, so ↩ pastes the latest copy")
    func emptyQuery() {
        #expect(ids("") == [1, 2, 4])
        #expect(ids("   ") == [1, 2, 4])
    }

    @Test("Searching History also finds saved items, listed first")
    func searchIncludesSaved() {
        #expect(ids("report") == [3])
        #expect(ids("l") == [3, 1, 2])  // "quarterly report", then "Hello", "Telegram"
        let sections = HistoryFilter.sections(of: items, query: "l")
        #expect(sections.saved.compactMap(\.id) == [3])
        #expect(sections.recent.compactMap(\.id) == [1, 2])
    }

    @Test("The Saved tab shows only saved items, with or without a search")
    func savedScope() {
        #expect(ids("", scope: .saved) == [3])
        #expect(ids("report", scope: .saved) == [3])
        #expect(ids("hello", scope: .saved).isEmpty)
    }

    @Test("Names are searched; a secret's search key never holds its value")
    func namesAndSecrets() {
        let named = ClipItem(
            id: 7, kind: .text, text: "sk-live-123", contentHash: "7", byteSize: 1,
            createdAt: referenceNow, lastUsedAt: referenceNow, isPinned: true, name: "OpenAI key"
        )
        let secret = ClipItem(
            id: 8, kind: .secret, text: nil, contentHash: "secret:x", byteSize: 0,
            createdAt: referenceNow, lastUsedAt: referenceNow, isPinned: true, name: "Bank PIN", secretRef: "x"
        )
        #expect(HistoryFilter.sections(of: [named, secret], query: "openai").all.compactMap(\.id) == [7])
        #expect(HistoryFilter.sections(of: [named, secret], query: "bank").all.compactMap(\.id) == [8])
        #expect(HistoryFilter.searchKey(for: secret) == "bank pin\nsecret\n")
        // The Saved tab has the named text; the Secrets tab has the secret.
        #expect(HistoryFilter.sections(of: [named, secret], query: "", scope: .saved).all.compactMap(\.id) == [7])
        #expect(HistoryFilter.sections(of: [named, secret], query: "", scope: .secrets).all.compactMap(\.id) == [8])
        #expect(HistoryScope.history.next == .saved)
        #expect(HistoryScope.secrets.next == .history)
        #expect(HistoryScope.history.previous == .secrets)
        #expect(named.displayTitle == "OpenAI key")
        #expect(secret.displayTitle == "Bank PIN")
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
