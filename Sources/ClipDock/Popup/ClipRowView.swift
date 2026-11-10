import ClipDockCore
import SwiftUI

/// One 36 pt row: type glyph (or multi-select number) · first line, thumbnail, or file name ·
/// badges · source app icon · age.
struct ClipRowView: View {
    let item: ClipItem
    let isSelected: Bool
    let markNumber: Int?
    let appIcon: NSImage?
    let thumbnails: ThumbnailCache

    var body: some View {
        HStack(spacing: 10) {
            leadingMark
                .frame(width: 18)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if item.isTranslation {
                Text("translated")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
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

    /// The order number while multi-selected, otherwise the type glyph.
    @ViewBuilder
    private var leadingMark: some View {
        if let markNumber {
            Text("\(markNumber)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
        } else {
            Image(systemName: Self.glyph(for: item.kind))
                .foregroundStyle(.secondary)
        }
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

/// The ⌘T result under a row: progress, the translation, or why it failed.
struct RowTranslationView: View {
    let state: RowTranslation.State

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "character.bubble")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            switch state {
            case .working:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Translating…").foregroundStyle(.secondary)
                }
            case .done(let text):
                VStack(alignment: .leading, spacing: 3) {
                    Text(text).lineLimit(4)
                    Text("↩ paste translation · ⌘C copy it")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
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
