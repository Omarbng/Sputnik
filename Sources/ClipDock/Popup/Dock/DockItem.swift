import AppKit

/// The dock's buttons, left to right (section 5.4). The toggle stays pinned at the right end.
enum DockItem: Int, CaseIterable, Identifiable {
    case history, pinned, translate, pasteAll, settings, toggle

    static let main: [DockItem] = [.history, .pinned, .translate, .pasteAll, .settings]

    var id: Int { rawValue }

    func symbol(collapsed: Bool) -> String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .pinned: "pin"
        case .translate: "character.bubble"
        case .pasteAll: "square.stack"
        case .settings: "gearshape"
        case .toggle: collapsed ? "chevron.left" : "chevron.right"
        }
    }

    func title(collapsed: Bool) -> String {
        switch self {
        case .history: "History"
        case .pinned: "Pinned"
        case .translate: "Translate"
        case .pasteAll: "Paste all"
        case .settings: "Settings"
        case .toggle: collapsed ? "Expand" : "Collapse"
        }
    }

    /// Shortcut keycaps shown in the tooltip, for example "Translate ⌘ T".
    var keys: [String] {
        switch self {
        case .translate: ["⌘", "T"]
        case .pasteAll: ["⌘", "↩"]
        case .settings: ["⌘", ","]
        default: []
        }
    }
}

/// Dock geometry (section 5.1): 8 pt padding, 32 pt buttons, 2 pt gaps, and a hairline divider
/// before the toggle.
enum DockLayout {
    static let padding: CGFloat = 8
    static let button: CGFloat = 32
    static let gap: CGFloat = 2
    static let dividerInset: CGFloat = 6

    static let dividerX = padding + CGFloat(DockItem.main.count) * button + CGFloat(DockItem.main.count - 1) * gap + dividerInset
    static let toggleX = dividerX + 1 + dividerInset
    static let expandedWidth = toggleX + button + padding
    static let collapsedWidth = padding * 2 + button

    static func x(of item: DockItem) -> CGFloat {
        item == .toggle ? toggleX : padding + CGFloat(item.rawValue) * (button + gap)
    }

    static func center(of item: DockItem) -> CGFloat {
        x(of: item) + button / 2
    }

    /// The button under a point in the dock's own coordinates, for hover.
    static func item(at point: CGPoint, collapsed: Bool) -> DockItem? {
        let candidates = collapsed ? [DockItem.toggle] : DockItem.allCases
        return candidates.first { item in
            let x = x(of: item)
            return point.x >= x - gap && point.x <= x + button + gap && point.y >= 0 && point.y <= padding * 2 + button
        }
    }
}
