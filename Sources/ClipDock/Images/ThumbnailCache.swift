import AppKit
import ClipDockCore

/// Downsampled image thumbnails, made off the main thread and kept in memory.
@MainActor
final class ThumbnailCache {
    private static let maxPixelSize = 160
    private let blobs: BlobStore
    private let cache = NSCache<NSString, NSImage>()

    init(blobs: BlobStore) {
        self.blobs = blobs
        cache.countLimit = 200
    }

    func cached(_ blobName: String) -> NSImage? {
        cache.object(forKey: blobName as NSString)
    }

    func load(_ blobName: String) async -> NSImage? {
        if let hit = cached(blobName) { return hit }
        let url = blobs.url(for: blobName)
        let maxPixelSize = Self.maxPixelSize
        let box = await Task.detached(priority: .userInitiated) {
            ImageBox(image: Thumbnailer.make(from: url, maxPixelSize: maxPixelSize))
        }.value
        guard let cgImage = box.image else { return nil }
        // Thumbnails are made at 2× for Retina, so the point size is half the pixel size.
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        cache.setObject(image, forKey: blobName as NSString)
        return image
    }
}

/// CGImage is immutable, so handing it across threads is safe.
private struct ImageBox: @unchecked Sendable {
    let image: CGImage?
}
