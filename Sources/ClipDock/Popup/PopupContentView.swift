import AppKit
import SwiftUI

/// The popup's AppKit shell: a blurred rounded background, the search field, and the SwiftUI
/// list. The search field is AppKit so it can be focused reliably on every open.
@MainActor
final class PopupContentView: NSView {
    static let cornerRadius: CGFloat = 12
    static let searchHeight: CGFloat = 44

    let searchField = NSTextField()

    init(list: some View) {
        super.init(frame: .zero)

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 15)
        searchField.placeholderString = "Search"
        searchField.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingTail

        let divider = NSBox()
        divider.boxType = .separator

        let hosting = NSHostingView(rootView: list)
        hosting.sizingOptions = []  // fixed-size panel: SwiftUI must not resize the window

        for view in [background, icon, searchField, divider, hosting] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(background)
        [icon, searchField, divider, hosting].forEach(background.addSubview)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: background.topAnchor, constant: Self.searchHeight / 2),
            icon.widthAnchor.constraint(equalToConstant: 16),

            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            searchField.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

            divider.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.searchHeight),
            divider.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: background.trailingAnchor),

            hosting.topAnchor.constraint(equalTo: divider.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// A stretchable rounded-rect mask, so the blur has rounded corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
