import ClipDockCore
import Observation

/// A ⌘T translation shown under one row.
struct RowTranslation: Equatable {
    enum State: Equatable {
        case working
        case done(String)
        case failed(String)
    }

    let itemID: Int64
    var state: State
}

/// Search text and selection for the popup. Rows come straight from `HistoryModel`.
@MainActor
@Observable
final class PopupViewModel {
    var query = "" {
        didSet { if query != oldValue { selectedIndex = 0 } }
    }
    private(set) var selectedIndex = 0
    /// Bumped on every open, so the list can scroll back to the top.
    private(set) var openCount = 0
    /// The ⌘T result under a row, if any.
    var translation: RowTranslation?
    /// Space-marked items for ⌘↩, in the order they were marked.
    var marks = MarkedSelection()

    /// Set by the popup controller. Called when a row is clicked.
    @ObservationIgnored var onPick: ((ClipItem) -> Void)?

    private let history: HistoryModel

    init(history: HistoryModel) {
        self.history = history
    }

    var sections: HistoryFilter.Sections {
        HistoryFilter.sections(of: history.items, query: query, keys: history.searchKeys)
    }

    var selectedItem: ClipItem? { item(at: selectedIndex) }

    /// The finished translation of the selected row. ↩ and ⌘C use it instead of the item.
    var selectedTranslation: String? {
        guard let translation, translation.itemID == selectedItem?.id,
              case .done(let text) = translation.state
        else { return nil }
        return text
    }

    /// The item at a visible position (pinned first, then recent).
    func item(at index: Int) -> ClipItem? {
        let all = sections.all
        return all.indices.contains(index) ? all[index] : nil
    }

    func prepareForOpen() {
        query = ""
        selectedIndex = 0
        translation = nil
        marks.removeAll()
        openCount += 1
    }

    func moveSelection(by delta: Int) {
        let count = sections.all.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    /// Keeps the selection and marks on real rows after the list shrinks (for example, after a delete).
    func clampSelection() {
        selectedIndex = min(selectedIndex, max(sections.all.count - 1, 0))
        marks.keep(only: Set(history.items.compactMap(\.id)))
    }

    /// The marked items, in marking order.
    var markedItems: [ClipItem] {
        marks.ids.compactMap { history.item(id: $0) }
    }
}
