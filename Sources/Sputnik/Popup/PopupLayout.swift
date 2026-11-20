import AppKit

/// Popup geometry (section 5.4). The panel is bigger than what you see: it has room above the
/// dock for the tooltip rail, and margins all round for the shadows. The transparent parts
/// let clicks through.
enum PopupLayout {
    static let cardWidth: CGFloat = 360
    static let cardCornerRadius: CGFloat = 18
    static let dockHeight: CGFloat = 48
    static let dockToCard: CGFloat = 8
    static let searchHeight: CGFloat = 44
    static let rowHeight: CGFloat = 36
    static let maxVisibleRows = 8
    static let cardHeight = searchHeight + 1 + CGFloat(maxVisibleRows) * rowHeight + 8

    /// The visible stack (dock and card). This is what's placed at the cursor.
    static let contentSize = CGSize(width: cardWidth, height: dockHeight + dockToCard + cardHeight)

    /// Tooltip rail: 32 pt tall, 12 pt above the dock.
    static let tooltipHeight: CGFloat = 32
    static let tooltipGap: CGFloat = 12
    static let shadowMargin: CGFloat = 40
    static let insets = NSEdgeInsets(
        top: shadowMargin + tooltipHeight + tooltipGap,
        left: shadowMargin,
        bottom: shadowMargin,
        right: shadowMargin
    )

    static let windowSize = CGSize(
        width: contentSize.width + insets.left + insets.right,
        height: contentSize.height + insets.top + insets.bottom
    )

    /// The panel frame for a content frame placed by `PopupPlacement`.
    static func windowFrame(forContent content: CGRect) -> CGRect {
        CGRect(
            x: content.minX - insets.left,
            y: content.minY - insets.bottom,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    /// The visible content inside a panel frame.
    static func contentFrame(inWindow window: CGRect) -> CGRect {
        CGRect(x: window.minX + insets.left, y: window.minY + insets.bottom, width: contentSize.width, height: contentSize.height)
    }
}
