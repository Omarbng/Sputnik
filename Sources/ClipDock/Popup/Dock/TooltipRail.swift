import AppKit
import SwiftUI

/// The tooltip rail (section 5.1): one inverted label surface 12 pt above the dock. Every
/// label sits side by side inside it. On hover the rail slides to sit over the hovered icon and
/// clips itself so only that icon's label shows. The first hover appears in place without
/// sliding; later hovers slide.
struct TooltipRail: View {
    let hovered: DockItem?
    let collapsed: Bool
    let tokens: Tokens

    @State private var visible = false
    @State private var clipX: CGFloat = 0
    @State private var clipWidth: CGFloat = 0
    @State private var contentOffset: CGFloat = 0

    var body: some View {
        let labels = TooltipLabelLayout(collapsed: collapsed)
        HStack(spacing: 0) {
            ForEach(DockItem.allCases) { item in
                TooltipLabel(title: item.title(collapsed: collapsed), keys: item.keys, tokens: tokens)
                    .frame(width: labels.width(of: item), height: PopupLayout.tooltipHeight)
            }
        }
        .fixedSize()
        .offset(x: contentOffset)
        .frame(width: clipWidth, height: PopupLayout.tooltipHeight, alignment: .leading)
        .background(tokens.primary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: tokens.shadow, radius: 16, x: 0, y: 8)
        .offset(x: clipX)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .onChange(of: hovered) { _, item in move(to: item) }
    }

    private func move(to item: DockItem?) {
        let reduce = Motion.reduceMotion
        guard let item else {
            withAnimation(Motion.fade(reduce)) { visible = false }
            return
        }
        let labels = TooltipLabelLayout(collapsed: collapsed)
        let width = labels.width(of: item)
        let x = DockLayout.center(of: item) - width / 2
        let offset = -labels.start(of: item)

        if !visible {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                clipX = x
                clipWidth = width
                contentOffset = offset
            }
            withAnimation(Motion.fade(reduce)) { visible = true }
        } else {
            withAnimation(Motion.slide(reduce)) {
                clipX = x
                contentOffset = offset
            }
            withAnimation(Motion.reveal(reduce)) { clipWidth = width }
        }
    }
}

/// Text 13 pt medium, −0.01 em tracking, 12 pt side padding, 8 pt gap, then 20 pt keycaps.
private struct TooltipLabel: View {
    let title: String
    let keys: [String]
    let tokens: Tokens

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.13)
                .lineLimit(1)
            if !keys.isEmpty {
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 20, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(tokens.primaryForeground.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .foregroundStyle(tokens.primaryForeground)
        .padding(.horizontal, 12)
    }
}

/// Label widths, measured once with the same font, so the rail can clip to one label exactly.
struct TooltipLabelLayout {
    let widths: [CGFloat]

    init(collapsed: Bool) {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        widths = DockItem.allCases.map { item in
            let text = (item.title(collapsed: collapsed) as NSString)
                .size(withAttributes: [.font: font, .kern: -0.13]).width.rounded(.up) + 2
            let keys = item.keys.isEmpty ? 0 : 8 + CGFloat(item.keys.count) * 20 + CGFloat(item.keys.count - 1) * 4
            return 12 + text + keys + 12
        }
    }

    func width(of item: DockItem) -> CGFloat { widths[item.rawValue] }
    func start(of item: DockItem) -> CGFloat { widths.prefix(item.rawValue).reduce(0, +) }
}
