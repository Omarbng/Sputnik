/// Search in the popup: case-insensitive, over the item's text and its source app's name.
/// Every word in the query must match. Pinned items come first, then recent ones.
public enum HistoryFilter {
    /// Only the start of very long texts is searched, so typing stays instant.
    public static let maxSearchedCharacters = 2_000

    public struct Sections: Equatable, Sendable {
        public var pinned: [ClipItem]
        public var recent: [ClipItem]
        /// Pinned then recent: the order rows appear in, and what ⌘1–⌘9 count.
        public var all: [ClipItem] { pinned + recent }
    }

    /// Lowercased text the query is matched against.
    public static func searchKey(for item: ClipItem) -> String {
        let content = item.kind == .image ? "image" : String((item.text ?? "").prefix(maxSearchedCharacters))
        return (content + "\n" + (item.sourceAppName ?? "")).lowercased()
    }

    public static func terms(in query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `keys` maps item IDs to precomputed search keys. Missing keys are computed on the fly.
    public static func sections(of items: [ClipItem], query: String, keys: [Int64: String] = [:]) -> Sections {
        let terms = terms(in: query)
        var pinned: [ClipItem] = []
        var recent: [ClipItem] = []
        for item in items {
            if !terms.isEmpty {
                let key = item.id.flatMap { keys[$0] } ?? searchKey(for: item)
                guard terms.allSatisfy({ key.contains($0) }) else { continue }
            }
            if item.isPinned { pinned.append(item) } else { recent.append(item) }
        }
        return Sections(pinned: pinned, recent: recent)
    }
}
