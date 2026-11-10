import ClipDockCore
import SwiftUI

/// One 36 pt row: type glyph (or multi-select number) · first line, thumbnail, or file name ·
/// badges · source app icon · age.
struct ClipRowView: View {
    let item: ClipItem
    let markNumber: Int?
    let appIcon: NSImage?
    let thumbnails: ThumbnailCache
    let tokens: Tokens

    var body: some View {
        HStack(spacing: 10) {
            leadingMark
                .frame(width: 18)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tokens.mutedForeground)
            }
            if item.isTranslation {
                Text("translated")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tokens.mutedForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(tokens.border, lineWidth: 1))
            }
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(RelativeTime.short(item.lastUsedAt))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(tokens.mutedForeground)
                .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: PopupLayout.rowHeight)
        .contentShape(Rectangle())
    }

    /// The order number while multi-selected, otherwise the type glyph.
    @ViewBuilder
    private var leadingMark: some View {
        if let markNumber {
            Text("\(markNumber)")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tokens.primaryForeground)
                .frame(width: 18, height: 18)
                .background(tokens.primary, in: Circle())
        } else {
            Image(systemName: Self.glyph(for: item.kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.mutedForeground)
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.kind == .image, let blob = item.imageBlob {
            ThumbnailView(blobName: blob, cache: thumbnails, tokens: tokens)
        } else {
            Text(item.title.isEmpty ? "(blank)" : item.title)
                .font(.system(size: 13))
                .foregroundStyle(tokens.foreground)
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
    let tokens: Tokens

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "character.bubble")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.mutedForeground)
                .frame(width: 18)
            switch state {
            case .working:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Translating…").foregroundStyle(tokens.mutedForeground)
                }
            case .done(let text):
                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .foregroundStyle(tokens.foreground)
                        .lineLimit(4)
                    Text("↩ paste translation · ⌘C copy it")
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.mutedForeground)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }
}

private struct ThumbnailView: View {
    let blobName: String
    let cache: ThumbnailCache
    let tokens: Tokens
    @State private var image: NSImage?

    init(blobName: String, cache: ThumbnailCache, tokens: Tokens) {
        self.blobName = blobName
        self.cache = cache
        self.tokens = tokens
        _image = State(initialValue: cache.cached(blobName))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tokens.accent)
                    .frame(width: 40)
            }
        }
        .frame(height: 26)
        .task(id: blobName) {
            if image == nil { image = await cache.load(blobName) }
        }
    }
}
