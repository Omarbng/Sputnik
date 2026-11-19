import ClipDockCore
import SwiftUI

/// One 36 pt row: type glyph (or multi-select number) · name and/or first line, thumbnail, or
/// file name · badges · source app icon · age. Under the pointer, the icon and age make way
/// for ⋯ (actions) and trash buttons. A saved item asks once more before it's deleted.
struct ClipRowView: View {
    let item: ClipItem
    let markNumber: Int?
    let appIcon: NSImage?
    let thumbnails: ThumbnailCache
    let tokens: Tokens
    var isHovered = false
    var isPendingDelete = false
    var onActions: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            leadingMark
                .frame(width: 18)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if isPendingDelete {
                deleteConfirmation
            } else if isHovered {
                hoverButtons
            } else {
                badges
            }
        }
        .padding(.horizontal, 18)
        .frame(height: PopupLayout.rowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badges: some View {
        if item.isPinned, !item.isSecret, item.name == nil {
            Image(systemName: "pin.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tokens.mutedForeground)
        }
        if item.isTranslation {
            badge("translated")
        }
        if item.isDictation {
            badge("dictated")
        }
        if item.expiresAt != nil {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tokens.mutedForeground)
                .help("Sensitive: leaves history 10 minutes after you copied it. ⌘P keeps it.")
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

    private func badge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tokens.mutedForeground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(tokens.border, lineWidth: 1))
    }

    private var hoverButtons: some View {
        HStack(spacing: 2) {
            RowIconButton(symbol: "ellipsis", help: "Actions (⌘K)", tokens: tokens, action: onActions)
            RowIconButton(symbol: "trash", help: "Delete (⌘⌫)", tokens: tokens, action: onDelete)
        }
    }

    private var deleteConfirmation: some View {
        Button(action: onDelete) {
            HStack(spacing: 4) {
                Image(systemName: "trash.fill")
                Text("Delete?")
                Keycaps(keys: ["⌘", "⌫"], color: .red)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.red)
            .padding(.leading, 8)
            .padding(.trailing, 3)
            .frame(height: 24)
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()  // the title truncates instead
        .help("Click or press ⌘⌫ again to delete")
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
        if item.kind == .image, let blob = item.imageBlob, item.name == nil {
            ThumbnailView(blobName: blob, cache: thumbnails, tokens: tokens)
        } else {
            HStack(spacing: 8) {
                Text(item.displayTitle.isEmpty ? "(blank)" : item.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    /// Next to a name: the content's start, or dots for a secret.
    private var detail: String? {
        guard item.name != nil else { return nil }
        return item.isSecret ? "••••••••" : item.title
    }

    static func glyph(for kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        case .secret: "lock.fill"
        }
    }
}

/// A 24 pt round icon button that fills with the accent colour on hover.
private struct RowIconButton: View {
    let symbol: String
    let help: String
    let tokens: Tokens
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovered ? tokens.foreground : tokens.mutedForeground)
                .frame(width: 24, height: 24)
                .background(hovered ? tokens.foreground.opacity(0.12) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// The result under a row (⌘T translation, or a writing action): progress, the result, or
/// why it failed.
struct RowTranslationView: View {
    let result: RowTranslation
    let tokens: Tokens

    var body: some View {
        let isRewrite = result.kind == .rewrite
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isRewrite ? "sparkles" : "character.bubble")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.mutedForeground)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                if let label = result.label {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.mutedForeground)
                }
                switch result.state {
                case .working:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(isRewrite ? "Writing…" : "Translating…").foregroundStyle(tokens.mutedForeground)
                    }
                case .done(let text):
                    Text(text)
                        .foregroundStyle(tokens.foreground)
                        .lineLimit(5)
                    Text(isRewrite ? "↩ paste it · ⌘C copy it" : "↩ paste translation · ⌘C copy it")
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.mutedForeground)
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                }
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
