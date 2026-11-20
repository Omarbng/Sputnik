import SputnikCore
import Observation

/// In-memory history, most recently used first. It mirrors the database, so the popup never
/// waits on disk.
@MainActor
@Observable
final class HistoryModel {
    private(set) var items: [ClipItem] = []

    /// Precomputed search keys by item ID, kept in step with `items`.
    @ObservationIgnored private(set) var searchKeys: [Int64: String] = [:]

    func replaceAll(with items: [ClipItem]) {
        self.items = items
        searchKeys = Dictionary(
            items.compactMap { item in item.id.map { ($0, HistoryFilter.searchKey(for: item)) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Applies one stored capture: expired items drop out and the item goes to the top.
    func apply(_ change: HistoryChange) {
        remove(ids: change.removedIDs)
        moveToTop(change.item)
    }

    /// Puts a new or updated item at the top.
    func moveToTop(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if let id = item.id {
            searchKeys[id] = HistoryFilter.searchKey(for: item)
        }
    }

    /// Replaces an item where it is (for example, after pinning), without moving it.
    func update(_ item: ClipItem) {
        guard let id = item.id, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = item
        searchKeys[id] = HistoryFilter.searchKey(for: item)
    }

    func item(id: Int64) -> ClipItem? {
        items.first { $0.id == id }
    }

    func remove(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let doomed = Set(ids)
        items.removeAll { item in item.id.map(doomed.contains) ?? true }
        for id in ids { searchKeys[id] = nil }
    }
}
