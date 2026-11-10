import AppKit
import ClipDockCore
import SwiftUI

/// The popup (section 5.4): the dock pill at the cursor, with the list card under it.
/// Collapsing hides the card, so only the dock is left.
struct PopupRootView: View {
    let model: PopupViewModel
    let icons: AppIconCache
    let thumbnails: ThumbnailCache
    let searchField: NSTextField
    let onDock: (DockItem) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        let reduce = Motion.reduceMotion
        VStack(alignment: .leading, spacing: PopupLayout.dockToCard) {
            DockView(model: model, onSelect: onDock)
            card(tokens)
                .opacity(model.isCollapsed ? 0 : 1)
                .offset(y: model.isCollapsed && !reduce ? -6 : 0)
                .animation(Motion.fade(reduce), value: model.isCollapsed)
                .allowsHitTesting(!model.isCollapsed)
        }
        .padding(.top, PopupLayout.insets.top)
        .padding(.leading, PopupLayout.insets.left)
        .frame(width: PopupLayout.windowSize.width, height: PopupLayout.windowSize.height, alignment: .topLeading)
    }

    private func card(_ tokens: Tokens) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.mutedForeground)
                SearchFieldView(field: searchField)
                if model.scope == .pinned {
                    Text("Pinned")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokens.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(tokens.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: PopupLayout.searchHeight)

            Rectangle().fill(tokens.border).frame(height: 1)

            PopupListView(model: model, icons: icons, thumbnails: thumbnails)
        }
        .frame(width: PopupLayout.cardWidth, height: PopupLayout.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: PopupLayout.cardCornerRadius, style: .continuous))
        .background(MaterialBackground(cornerRadius: PopupLayout.cardCornerRadius))
    }
}

/// The search box is an AppKit text field, so the controller can focus it reliably on every
/// open. SwiftUI only places it.
private struct SearchFieldView: NSViewRepresentable {
    let field: NSTextField

    func makeNSView(context: Context) -> NSTextField { field }
    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

extension NSTextField {
    /// Borderless, transparent search field for the popup card.
    static func popupSearchField() -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = .labelColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 14)]
        )
        return field
    }
}
