import Foundation

/// One pasteboard change, read and classified, before it is stored.
public struct CapturedClip: Sendable, Equatable {
    public var payload: ClipPayload
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var capturedAt: Date
    /// A translation ClipDock made, rather than something the user copied.
    public var isTranslation: Bool

    public init(
        payload: ClipPayload,
        sourceBundleID: String?,
        sourceAppName: String?,
        capturedAt: Date,
        isTranslation: Bool = false
    ) {
        self.payload = payload
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.capturedAt = capturedAt
        self.isTranslation = isTranslation
    }

    public var kind: ClipKind {
        switch payload {
        case .text: .text
        case .url: .url
        case .files: .file
        case .image: .image
        }
    }

    /// What goes in the `text` column: plain text, the URL, or newline-joined file paths.
    public var storedText: String? {
        switch payload {
        case .text(let string, _): string
        case .url(let string): string
        case .files(let paths): paths.joined(separator: "\n")
        case .image: nil
        }
    }

    public var rtf: Data? {
        if case .text(_, let rtf) = payload { rtf } else { nil }
    }

    public var imageData: Data? {
        if case .image(let data, _) = payload { data } else { nil }
    }

    /// Bytes we would store. Used for the size limit.
    public var byteSize: Int {
        (storedText?.utf8.count ?? 0) + (rtf?.count ?? 0) + (imageData?.count ?? 0)
    }

    /// Dedupe key: same kind + same content means the same item.
    public var contentHash: String {
        ContentHash.of(kind: kind, text: storedText, image: imageData)
    }

    /// Converts non-PNG images to PNG. Returns nil if the image can't be decoded.
    /// Call this off the main thread; large images take a while.
    public func normalized() -> CapturedClip? {
        guard case .image(let data, isPNG: false) = payload else { return self }
        guard let png = PNGConverter.png(from: data) else { return nil }
        var copy = self
        copy.payload = .image(png, isPNG: true)
        return copy
    }
}
