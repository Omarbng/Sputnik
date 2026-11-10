import ClipDockCore
import SwiftUI

/// The history list: Pinned on top (when there are any), then Recent. The selected row is a
/// soft filled capsule that slides between rows with the tooltip-slide spring.
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
                .font(.system(size: 13))
                .foregroundStyle(tokens.mutedForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !sections.pinned.isEmpty, model.scope == .history {
                            header("Pinned", tokens)
                        }
                        rows(sections.pinned, selectedID: selectedID, tokens: tokens)
                        if !sections.pinned.isEmpty, !sections.recent.isEmpty {
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
        return model.scope == .pinned ? "No pinned items — ⌘P pins one" : "Nothing copied yet"
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
                    tokens: tokens
                )
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
                    RowTranslationView(state: translation.state, tokens: tokens)
                }
            }
            .id(item.id ?? -1)
        }
    }
}
