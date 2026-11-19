import ClipDockCore
import SwiftUI

/// Quick Look (⇧Space, ⌘Y): the whole text or the full image, in place of the list.
/// ↑↓ show the neighbouring items, ↩ pastes, ⌘C copies, Esc or Space closes.
struct PeekView: View {
    let item: ClipItem
    let tokens: Tokens
    /// Loads the full image (blob or file), off the main thread.
    let imageData: (ClipItem) -> Data?

    @State private var image: NSImage?
    @State private var pixelSize: CGSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .frame(height: PopupLayout.searchHeight)
            Rectangle().fill(tokens.border).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("↑↓ next  ·  ↩ paste  ·  ⌘C copy  ·  esc close")
                .font(.system(size: 11))
                .foregroundStyle(tokens.mutedForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
        }
        .task(id: item.id) { await loadImage() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: ClipRowView.glyph(for: item.kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.mutedForeground)
            Text(item.displayTitle.isEmpty ? "(blank)" : item.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.foreground)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(details)
                .font(.system(size: 11))
                .foregroundStyle(tokens.mutedForeground)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.kind == .image || item.imageFilePath != nil {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
        } else {
            ScrollView {
                Text(String((item.text ?? "").prefix(20_000)))
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
    }

    /// "Safari · 2m · 1,240 characters" or "Preview · 5m · 1920 × 1080".
    private var details: String {
        var parts: [String] = []
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(RelativeTime.short(item.lastUsedAt))
        if let pixelSize {
            parts.append("\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
        } else if let text = item.text, item.kind == .text {
            let words = text.split(whereSeparator: \.isWhitespace).count
            parts.append("\(words) word\(words == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func loadImage() async {
        image = nil
        pixelSize = nil
        guard item.kind == .image || item.imageFilePath != nil, let data = imageData(item) else { return }
        let size = ImageTools.pixelSize(of: data)
        let loaded = await Task.detached(priority: .userInitiated) { NSImageBox(NSImage(data: data)) }.value
        image = loaded.image
        pixelSize = size
    }
}

/// NSImage built off the main thread and handed over once; it isn't touched again there.
private struct NSImageBox: @unchecked Sendable {
    let image: NSImage?
    init(_ image: NSImage?) { self.image = image }
}
