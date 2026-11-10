import ClipDockCore
import SwiftUI

/// The history list: Pinned on top (when there are any), then Recent.
struct PopupListView: View {
    let model: PopupViewModel
    let icons: AppIconCache
    let thumbnails: ThumbnailCache

    var body: some View {
        let sections = model.sections
        let all = sections.all
        let selectedID = all.indices.contains(model.selectedIndex) ? all[model.selectedIndex].id : nil

        if all.isEmpty {
            Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !sections.pinned.isEmpty {
                            header("Pinned")
                            rows(sections.pinned, selectedID: selectedID)
                            header("Recent")
                        }
                        rows(sections.recent, selectedID: selectedID)
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.automatic)
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
                .onChange(of: model.openCount) {
                    if let first = model.sections.all.first?.id { proxy.scrollTo(first, anchor: .top) }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func rows(_ items: [ClipItem], selectedID: Int64?) -> some View {
        ForEach(items, id: \.id) { item in
            VStack(spacing: 0) {
                ClipRowView(
                    item: item,
                    isSelected: item.id == selectedID,
                    appIcon: icons.icon(for: item.sourceBundleID),
                    thumbnails: thumbnails
                )
                .onTapGesture { model.onPick?(item) }
                if let translation = model.translation, translation.itemID == item.id {
                    RowTranslationView(state: translation.state)
                }
            }
            .id(item.id ?? -1)
        }
    }
}
