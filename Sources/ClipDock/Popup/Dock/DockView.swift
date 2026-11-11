import ClipDockCore
import SwiftUI

/// The dock pill (section 5.1): a 48 pt capsule of 32 pt icon buttons, with the collapse toggle
/// pinned at the right end. Collapsing slides the icons into the toggle and shrinks the pill
/// toward it. The toggle itself never moves.
struct DockView: View {
    let model: PopupViewModel
    let onSelect: (DockItem) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        let reduce = Motion.reduceMotion
        let collapsed = model.isCollapsed
        let width = collapsed ? DockLayout.collapsedWidth : DockLayout.expandedWidth

        ZStack(alignment: .topLeading) {
            MaterialBackground(cornerRadius: nil)
                .frame(width: width, height: PopupLayout.dockHeight)
                .offset(x: DockLayout.expandedWidth - width)
                .animation(Motion.collapse(reduce), value: collapsed)

            ZStack(alignment: .topLeading) {
                ForEach(DockItem.main) { item in
                    DockButton(
                        symbol: item.symbol(collapsed: collapsed),
                        isLit: model.hoveredDockItem == item || isActive(item),
                        showsBadge: showsBadge(item),
                        tokens: tokens,
                        label: item.title(collapsed: collapsed),
                        action: { onSelect(item) }
                    )
                    .offset(x: collapsed ? DockLayout.toggleX : DockLayout.x(of: item), y: DockLayout.padding)
                    .animation(Motion.collapse(reduce), value: collapsed)
                    .opacity(collapsed ? 0 : 1)
                    .animation(Motion.fade(reduce), value: collapsed)
                    .allowsHitTesting(!collapsed)
                }
                Rectangle()
                    .fill(tokens.border)
                    .frame(width: 1, height: 20)
                    .offset(x: DockLayout.dividerX, y: (PopupLayout.dockHeight - 20) / 2)
                    .opacity(collapsed ? 0 : 1)
                    .animation(Motion.fade(reduce), value: collapsed)
            }
            // Icons slide into the toggle under the shrinking pill, so clip them to it.
            .mask(alignment: .topLeading) {
                Capsule()
                    .frame(width: width, height: PopupLayout.dockHeight)
                    .offset(x: DockLayout.expandedWidth - width)
                    .animation(Motion.collapse(reduce), value: collapsed)
            }

            DockButton(
                symbol: DockItem.toggle.symbol(collapsed: collapsed),
                isLit: model.hoveredDockItem == .toggle,
                showsBadge: false,
                tokens: tokens,
                label: DockItem.toggle.title(collapsed: collapsed),
                action: { onSelect(.toggle) }
            )
            .offset(x: DockLayout.toggleX, y: DockLayout.padding)
        }
        .frame(width: DockLayout.expandedWidth, height: PopupLayout.dockHeight, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            TooltipRail(hovered: model.hoveredDockItem, collapsed: collapsed, tokens: tokens)
                .offset(y: -(PopupLayout.tooltipGap + PopupLayout.tooltipHeight))
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): model.hoveredDockItem = DockLayout.item(at: point, collapsed: collapsed)
            case .ended: model.hoveredDockItem = nil
            }
        }
    }

    private func isActive(_ item: DockItem) -> Bool {
        switch item {
        case .history: model.scope == .history
        case .saved: model.scope == .saved
        default: false
        }
    }

    private func showsBadge(_ item: DockItem) -> Bool {
        switch item {
        case .saved: model.hasSaved
        case .pasteAll: !model.marks.isEmpty
        default: false
        }
    }
}

/// A 32 pt circular icon button. Hover (or the active scope) fills it with the accent colour.
/// The badge is an 8 pt dot, inset 6 pt from the top-right, with a 1.7 pt ring in the
/// background colour.
private struct DockButton: View {
    let symbol: String
    let isLit: Bool
    let showsBadge: Bool
    let tokens: Tokens
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))  // ≈ the reference's 2 pt stroke
                .foregroundStyle(tokens.foreground)
                .frame(width: DockLayout.button, height: DockLayout.button)
                .background(Circle().fill(isLit ? tokens.accent : .clear))
                .animation(Motion.fade(Motion.reduceMotion), value: isLit)
                .overlay(alignment: .topTrailing) {
                    if showsBadge {
                        ZStack {
                            Circle().fill(tokens.background).frame(width: 8 + 3.4, height: 8 + 3.4)
                            Circle().fill(tokens.primary).frame(width: 8, height: 8)
                        }
                        .padding(6 - 1.7)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
