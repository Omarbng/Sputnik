/// The popup's two tabs (the dock's first two buttons).
public enum HistoryScope: Sendable, Equatable {
    /// What you copied. Saved items join in only while you search.
    case history
    /// Pinned clips, typed-in items, and secrets.
    case saved
}

/// Search in the popup: case-insensitive, over the item's name, its text, and its source app's
/// name. Every word in the query must match. Saved items come first, then recent ones.
public enum HistoryFilter {
    /// Only the start of very long texts is searched, so typing stays instant.
    public static let maxSearchedCharacters = 2_000

    public struct Sections: Equatable, Sendable {
        public var saved: [ClipItem]
        public var recent: [ClipItem]

        public init(saved: [ClipItem], recent: [ClipItem]) {
            self.saved = saved
            self.recent = recent
        }
        /// Saved then recent: the order rows appear in, and what ⌘1–⌘9 count.
        public var all: [ClipItem] { saved + recent }
    }

    /// Lowercased text the query is matched against. A secret's value is never in it.
    public static func searchKey(for item: ClipItem) -> String {
        let content = switch item.kind {
        case .image: "image"
        case .secret: "secret"
        case .text, .url, .file: String((item.text ?? "").prefix(maxSearchedCharacters))
        }
        return [item.name ?? "", content, item.sourceAppName ?? ""].joined(separator: "\n").lowercased()
    }

    public static func terms(in query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `keys` maps item IDs to precomputed search keys. Missing keys are computed on the fly.
    /// History without a search shows only unsaved items, so ↩ and ⌘1 always reach what you
    /// copied last; saved items live in their own tab and join any search.
    public static func sections(
        of items: [ClipItem], query: String, keys: [Int64: String] = [:], scope: HistoryScope = .history
    ) -> Sections {
        let terms = terms(in: query)
        let showsSaved = scope == .saved || !terms.isEmpty
        let showsRecent = scope == .history
        var saved: [ClipItem] = []
        var recent: [ClipItem] = []
        for item in items {
            guard item.isPinned ? showsSaved : showsRecent else { continue }
            if !terms.isEmpty {
                let key = item.id.flatMap { keys[$0] } ?? searchKey(for: item)
                guard terms.allSatisfy({ key.contains($0) }) else { continue }
            }
            if item.isPinned { saved.append(item) } else { recent.append(item) }
        }
        return Sections(saved: saved, recent: recent)
    }
}
