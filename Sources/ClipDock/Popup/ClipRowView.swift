import ClipDockCore
import SwiftUI

/// One 36 pt row: type glyph · first line, thumbnail, or file name · source app icon · age.
struct ClipRowView: View {
    let item: ClipItem
    let isSelected: Bool
    let appIcon: NSImage?
    let thumbnails: ThumbnailCache

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.glyph(for: item.kind))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(RelativeTime.short(item.lastUsedAt))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var content: some View {
        if item.kind == .image, let blob = item.imageBlob {
            ThumbnailView(blobName: blob, cache: thumbnails)
        } else {
            Text(item.title.isEmpty ? "(blank)" : item.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    static func glyph(for kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

private struct ThumbnailView: View {
    let blobName: String
    let cache: ThumbnailCache
    @State private var image: NSImage?

    init(blobName: String, cache: ThumbnailCache) {
        self.blobName = blobName
        self.cache = cache
        _image = State(initialValue: cache.cached(blobName))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(width: 40)
            }
        }
        .frame(height: 26)
        .task(id: blobName) {
            if image == nil { image = await cache.load(blobName) }
        }
    }
}
