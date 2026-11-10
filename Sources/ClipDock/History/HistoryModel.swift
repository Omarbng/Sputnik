import ClipDockCore
import Observation

/// In-memory history, most recently used first. It mirrors the database, so the popup never
/// waits on disk.
@MainActor
@Observable
final class HistoryModel {
    private(set) var items: [ClipItem] = []

    func replaceAll(with items: [ClipItem]) {
        self.items = items
    }

    /// Applies one stored capture: the item goes to the top and expired items drop out.
    func apply(_ change: HistoryChange) {
        let removed = Set(change.removedIDs)
        items.removeAll { item in
            guard let id = item.id else { return true }
            return id == change.item.id || removed.contains(id)
        }
        items.insert(change.item, at: 0)
    }
}
