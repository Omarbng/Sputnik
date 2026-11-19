import ClipDockCore
import SwiftUI

/// The list: in History, recent copies (plus matching saved items while searching); in Saved,
/// the saved items. The selected row is a soft filled capsule that slides between rows with the
/// tooltip-slide spring.
struct PopupListView: View {
    let model: PopupViewModel
    let icons: AppIconCache
    let thumbnails: ThumbnailCache

    @Environment(\.colorScheme) private var scheme
    @Namespace private var selection

    var body: some View {
        let tokens = Tokens.for(scheme)
        let sections = model.sections
        let all = sections.all
        let selectedID = all.indices.contains(model.selectedIndex) ? all[model.selectedIndex].id : nil

        if all.isEmpty {
            Text(emptyMessage)
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .foregroundStyle(tokens.mutedForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !sections.saved.isEmpty, model.scope == .history {
                            header("Saved", tokens)
                        }
                        rows(sections.saved, selectedID: selectedID, tokens: tokens)
                        if !sections.saved.isEmpty, !sections.recent.isEmpty {
                            header("Recent", tokens)
                        }
                        rows(sections.recent, selectedID: selectedID, tokens: tokens)
                    }
                    .padding(.vertical, 4)
                    .animation(Motion.slide(Motion.reduceMotion), value: selectedID)
                }
                .scrollIndicators(.never)
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
                .onChange(of: model.openCount) {
                    if let first = model.sections.all.first?.id { proxy.scrollTo(first, anchor: .top) }
                }
            }
        }
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No matches" }
        return switch model.scope {
        case .history: "Nothing copied yet"
        case .saved: "Nothing saved yet\n⌘N types one in · ⌘P saves a copied one"
        case .secrets: "No secrets yet\nCopy a key, then press ⌘V here\nor press ⌘L on it in History"
        }
    }

    private func header(_ title: String, _ tokens: Tokens) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tokens.mutedForeground)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func rows(_ items: [ClipItem], selectedID: Int64?, tokens: Tokens) -> some View {
        ForEach(items, id: \.id) { item in
            VStack(spacing: 0) {
                ClipRowView(
                    item: item,
                    markNumber: item.id.flatMap { model.marks.number(for: $0) },
                    appIcon: icons.icon(for: item.sourceBundleID),
                    thumbnails: thumbnails,
                    tokens: tokens,
                    isHovered: item.id != nil && model.hoveredItemID == item.id && model.actionMenu == nil,
                    isPendingDelete: item.id != nil && model.pendingDeleteID == item.id,
                    onActions: { model.onShowActions?(item) },
                    onDelete: { model.onRequestDelete?(item) }
                )
                .onHover { inside in
                    if inside {
                        model.hoveredItemID = item.id
                    } else if model.hoveredItemID == item.id {
                        model.hoveredItemID = nil
                    }
                }
                .background {
                    if item.id == selectedID {
                        Capsule(style: .continuous)
                            .fill(tokens.accent)
                            .padding(.horizontal, 6)
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
                .onTapGesture { model.onPick?(item) }
                if let translation = model.translation, translation.itemID == item.id {
                    RowTranslationView(result: translation, tokens: tokens)
                }
            }
            .id(item.id ?? -1)
        }
    }
}
