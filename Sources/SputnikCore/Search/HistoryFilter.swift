/// The popup's tabs (the dock's first three buttons). ⇥ moves through them in this order.
public enum HistoryScope: Sendable, Equatable, CaseIterable {
    /// What you copied. Saved items and secrets join in only while you search.
    case history
    /// Pinned clips and typed-in items.
    case saved
    /// Passwords and keys, kept in the Keychain.
    case secrets

    public var next: HistoryScope { Self.allCases[(index + 1) % Self.allCases.count] }
    public var previous: HistoryScope { Self.allCases[(index + Self.allCases.count - 1) % Self.allCases.count] }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
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
    /// copied last; saved items and secrets live in their own tabs and join any History search.
    public static func sections(
        of items: [ClipItem], query: String, keys: [Int64: String] = [:], scope: HistoryScope = .history
    ) -> Sections {
        let terms = terms(in: query)
        var saved: [ClipItem] = []
        var recent: [ClipItem] = []
        for item in items {
            let shown = switch scope {
            case .history: !item.isPinned || !terms.isEmpty
            case .saved: item.isPinned && !item.isSecret
            case .secrets: item.isSecret
            }
            guard shown else { continue }
            if !terms.isEmpty {
                let key = item.id.flatMap { keys[$0] } ?? searchKey(for: item)
                guard terms.allSatisfy({ key.contains($0) }) else { continue }
            }
            if item.isPinned { saved.append(item) } else { recent.append(item) }
        }
        return Sections(saved: saved, recent: recent)
    }
}
