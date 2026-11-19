import ClipDockCore
import SwiftUI

/// The actions menu: a small card over the list, with one row per action and its shortcut.
/// ↑↓ move, ↩ runs, Esc closes. The shortcuts also work directly, without opening it.
struct ActionMenuView: View {
    static let width: CGFloat = 244
    static let rowHeight: CGFloat = 22  // eleven actions still fit inside the card, like a native menu

    let menu: ActionMenuState
    let item: ClipItem
    let tokens: Tokens
    let onRun: (ClipAction) -> Void
    let onHover: (Int) -> Void

    @Namespace private var highlight

    /// Taller menus (text with a phone number and the writing actions) scroll inside the card.
    static let maxHeight: CGFloat = PopupLayout.cardHeight - PopupLayout.searchHeight - 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.displayTitle.isEmpty ? "(blank)" : item.displayTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.mutedForeground)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 22, alignment: .leading)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(menu.actions.enumerated()), id: \.element) { index, action in
                            if index > 0, menu.actions[index - 1].group != action.group {
                                Rectangle().fill(tokens.border).frame(height: 1).padding(.vertical, 2)
                            }
                            row(action, index: index).id(index)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: Self.listHeight(for: menu.actions))
                .onChange(of: menu.highlighted) { _, index in proxy.scrollTo(index) }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(width: Self.width)
        .animation(Motion.slide(Motion.reduceMotion), value: menu.highlighted)
        .background(MaterialBackground(cornerRadius: 12))
    }

    /// The rows' natural height, capped so the menu fits in the card.
    static func listHeight(for actions: [ClipAction]) -> CGFloat {
        let dividers = zip(actions, actions.dropFirst()).filter { $0.group != $1.group }.count
        let natural = CGFloat(actions.count) * rowHeight + CGFloat(dividers) * 5
        return min(natural, maxHeight - 30)
    }

    private func row(_ action: ClipAction, index: Int) -> some View {
        let color = action == .delete ? Color.red : tokens.foreground
        return HStack(spacing: 8) {
            Text(action.title(for: item))
                .font(.system(size: 13))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 8)
            Keycaps(keys: action.keys, color: tokens.mutedForeground)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background {
            if index == menu.highlighted {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tokens.accent)
                    .matchedGeometryEffect(id: "highlight", in: highlight)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in if inside { onHover(index) } }
        .onTapGesture { onRun(action) }
    }
}
