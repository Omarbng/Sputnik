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

/// The actions menu (⌘K, right-click, or a row's ⋯ button) for one item.
struct ActionMenuState: Equatable {
    let itemID: Int64
    let actions: [ClipAction]
    var highlighted = 0
}

/// The editor shown in place of the list: ⌘N types in a new saved item, ⌘E edits one.
struct EditorState: Equatable {
    enum Mode: Equatable {
        case new
        case edit(Int64)
    }

    var mode: Mode
    /// Saved items can have a name; plain history items can't.
    var showsName: Bool
    var isSecret: Bool
    /// A problem with what was typed, shown under the fields.
    var message: String?

    /// ⌘L works only while making a new item. An existing item can't change kind.
    var canToggleSecret: Bool { mode == .new }
    /// ⌘↩ pastes the edited text. New items and secrets only save.
    var canPaste: Bool { mode != .new && !isSecret }

    var title: String {
        switch mode {
        case .new: isSecret ? "New secret" : "New saved item"
        case .edit: isSecret ? "Edit secret" : "Edit"
        }
    }
}

/// Search text, selection, and the popup's modes. Rows come straight from `HistoryModel`.
@MainActor
@Observable
final class PopupViewModel {
    var scope = HistoryScope.history {
        didSet { if scope != oldValue { selectedIndex = 0 } }
    }
    /// The dock's collapse toggle: the list card hides and only the dock is left.
    var isCollapsed = false
    /// The dock button under the pointer, which drives the tooltip rail.
    var hoveredDockItem: DockItem?
    /// The row under the pointer: it shows its ⋯ and trash buttons, and a right-click acts on it.
    var hoveredItemID: Int64?

    var query = "" {
        didSet { if query != oldValue { selectedIndex = 0 } }
    }
    private(set) var selectedIndex = 0 {
        didSet { if selectedIndex != oldValue { pendingDeleteID = nil } }
    }
    /// Bumped on every open, so the list can scroll back to the top.
    private(set) var openCount = 0
    /// The ⌘T result under a row, if any.
    var translation: RowTranslation?
    /// Space-marked items for ⌘↩, in the order they were marked.
    var marks = MarkedSelection()
    var actionMenu: ActionMenuState?
    var editor: EditorState?
    /// A saved item waiting for a second ⌘⌫ (or click) before it's deleted.
    var pendingDeleteID: Int64?

    /// Set by the popup controller.
    @ObservationIgnored var onPick: ((ClipItem) -> Void)?
    @ObservationIgnored var onShowActions: ((ClipItem) -> Void)?
    @ObservationIgnored var onRequestDelete: ((ClipItem) -> Void)?
    @ObservationIgnored var onRunAction: ((ClipAction, ClipItem) -> Void)?
    @ObservationIgnored var onEditorCommand: ((EditorCommand) -> Void)?
    @ObservationIgnored var onNewSaved: (() -> Void)?
    @ObservationIgnored var onSaveCopiedSecret: (() -> Void)?

    private let history: HistoryModel

    init(history: HistoryModel) {
        self.history = history
    }

    var sections: HistoryFilter.Sections {
        HistoryFilter.sections(of: history.items, query: query, keys: history.searchKeys, scope: scope)
    }

    var hasSaved: Bool { history.items.contains { $0.isPinned && !$0.isSecret } }

    var selectedItem: ClipItem? { item(at: selectedIndex) }

    /// The finished translation of the selected row. ↩ and ⌘C use it instead of the item.
    var selectedTranslation: String? {
        guard let translation, translation.itemID == selectedItem?.id,
              case .done(let text) = translation.state
        else { return nil }
        return text
    }

    /// The item at a visible position (saved first, then recent).
    func item(at index: Int) -> ClipItem? {
        let all = sections.all
        return all.indices.contains(index) ? all[index] : nil
    }

    func item(id: Int64) -> ClipItem? {
        history.item(id: id)
    }

    /// The item the actions menu is open for.
    var actionMenuItem: ClipItem? {
        actionMenu.flatMap { history.item(id: $0.itemID) }
    }

    func prepareForOpen() {
        query = ""
        scope = .history
        isCollapsed = false
        hoveredDockItem = nil
        hoveredItemID = nil
        selectedIndex = 0
        translation = nil
        marks.removeAll()
        actionMenu = nil
        editor = nil
        pendingDeleteID = nil
        openCount += 1
    }

    func moveSelection(by delta: Int) {
        let count = sections.all.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    /// Selects a visible row by item, if it's in the list.
    func select(_ item: ClipItem) {
        if let index = sections.all.firstIndex(where: { $0.id == item.id }) { selectedIndex = index }
    }

    /// Keeps the selection and marks on real rows after the list shrinks (for example, after a delete).
    func clampSelection() {
        selectedIndex = min(selectedIndex, max(sections.all.count - 1, 0))
        marks.keep(only: Set(history.items.compactMap(\.id)))
    }

    func moveActionHighlight(by delta: Int) {
        guard var menu = actionMenu, !menu.actions.isEmpty else { return }
        menu.highlighted = (menu.highlighted + delta + menu.actions.count) % menu.actions.count
        actionMenu = menu
    }

    /// The marked items, in marking order.
    var markedItems: [ClipItem] {
        marks.ids.compactMap { history.item(id: $0) }
    }
}
