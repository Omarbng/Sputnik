import ClipDockCore
import SwiftUI

/// The actions menu: a small card over the list, with one row per action and its shortcut.
/// ↑↓ move, ↩ runs, Esc closes. The shortcuts also work directly, without opening it.
struct ActionMenuView: View {
    static let width: CGFloat = 244
    static let rowHeight: CGFloat = 24  // ten actions still fit inside the card

    let menu: ActionMenuState
    let item: ClipItem
    let tokens: Tokens
    let onRun: (ClipAction) -> Void
    let onHover: (Int) -> Void

    @Namespace private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.displayTitle.isEmpty ? "(blank)" : item.displayTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.mutedForeground)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 22, alignment: .leading)
            ForEach(Array(menu.actions.enumerated()), id: \.element) { index, action in
                if action.startsGroup, index > 0 {
                    Rectangle().fill(tokens.border).frame(height: 1).padding(.vertical, 2)
                }
                row(action, index: index)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .frame(width: Self.width)
        .animation(Motion.slide(Motion.reduceMotion), value: menu.highlighted)
        .background(MaterialBackground(cornerRadius: 12))
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
