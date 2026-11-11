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
    let editorFields: EditorFields
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
        ZStack(alignment: .topTrailing) {
            // The list stays in place under the editor, so the search field keeps its view.
            listCard(tokens)
                .opacity(model.editor == nil ? 1 : 0)
                .allowsHitTesting(model.editor == nil)
            if let editor = model.editor {
                EditorView(state: editor, fields: editorFields, tokens: tokens) { command in
                    model.onEditorCommand?(command)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let menu = model.actionMenu, let item = model.actionMenuItem {
                // A click anywhere else in the card closes the menu.
                Color.black.opacity(0.001)
                    .onTapGesture { model.actionMenu = nil }
                ActionMenuView(
                    menu: menu, item: item, tokens: tokens,
                    onRun: { action in model.onRunAction?(action, item) },
                    onHover: { index in model.actionMenu?.highlighted = index }
                )
                .padding(.top, PopupLayout.searchHeight + 4)
                .padding(.trailing, 8)
                .transition(.opacity)
            }
        }
        .animation(Motion.fade(Motion.reduceMotion), value: model.actionMenu?.itemID)
        .frame(width: PopupLayout.cardWidth, height: PopupLayout.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: PopupLayout.cardCornerRadius, style: .continuous))
        .background(MaterialBackground(cornerRadius: PopupLayout.cardCornerRadius))
    }

    private func listCard(_ tokens: Tokens) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.mutedForeground)
                HostedView(view: searchField)
                if model.scope == .saved {
                    Button { model.onNewSaved?() } label: {
                        HStack(spacing: 5) {
                            Text("Saved")
                            Keycaps(keys: ["⌘", "N"], color: tokens.mutedForeground)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokens.mutedForeground)
                        .padding(.leading, 8)
                        .padding(.trailing, 3)
                        .frame(height: 24)
                        .background(tokens.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("New saved item (⌘N)")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: PopupLayout.searchHeight)

            Rectangle().fill(tokens.border).frame(height: 1)

            PopupListView(model: model, icons: icons, thumbnails: thumbnails)
        }
    }
}

/// The search box is an AppKit text field (placed with `HostedView`), so the controller can
/// focus it reliably on every open.
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
        field.placeholderAttributedString = .placeholder("Search", size: 14)
        return field
    }
}
