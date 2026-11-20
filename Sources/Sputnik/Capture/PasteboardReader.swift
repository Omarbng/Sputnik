import AppKit
import SputnikCore

/// Turns the current pasteboard into a `CapturedClip`, or says why it's skipped.
/// Runs on the main thread, so it only reads. Image conversion happens later, in the pipeline.
@MainActor
struct PasteboardReader {
    enum Result {
        case skipped(SkipReason)
        case captured(CapturedClip)
    }

    func read(_ pasteboard: NSPasteboard, rules: SkipRules, source: NSRunningApplication?, now: Date) -> Result {
        let types = Self.allTypes(on: pasteboard)
        if let reason = rules.reasonBeforeReading(types: types, sourceBundleID: source?.bundleIdentifier) {
            return .skipped(reason)
        }
        guard let payload = Self.payload(from: pasteboard, types: Set(types)) else {
            return .skipped(.empty)
        }
        return .captured(CapturedClip(
            payload: payload,
            sourceBundleID: source?.bundleIdentifier,
            sourceAppName: source?.localizedName,
            capturedAt: now
        ))
    }

    /// Types across every item, because marker types can sit on any of them.
    private static func allTypes(on pasteboard: NSPasteboard) -> [String] {
        var types = (pasteboard.types ?? []).map(\.rawValue)
        for item in pasteboard.pasteboardItems ?? [] {
            types.append(contentsOf: item.types.map(\.rawValue))
        }
        return types
    }

    /// Priority: files, then text or URL, then image. A lone web URL that comes with an image
    /// (a browser's "Copy Image") counts as the image.
    private static func payload(from pasteboard: NSPasteboard, types: Set<String>) -> ClipPayload? {
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
           let urls = pasteboard.readObjects(
               forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
           ) as? [URL],
           !urls.isEmpty {
            return .files(urls.map { $0.path(percentEncoded: false) })
        }
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let textPayload = ClipPayload.fromText(string, rtf: pasteboard.data(forType: .rtf))
            if case .url = textPayload, let image = image(from: pasteboard, types: types) {
                return image
            }
            return textPayload
        }
        if let image = image(from: pasteboard, types: types) {
            return image
        }
        if let url = pasteboard.string(forType: .URL), !url.isEmpty {
            return .url(url)
        }
        return nil
    }

    private static func image(from pasteboard: NSPasteboard, types: Set<String>) -> ClipPayload? {
        if types.contains(NSPasteboard.PasteboardType.png.rawValue), let png = pasteboard.data(forType: .png) {
            return .image(png, isPNG: true)
        }
        if types.contains(NSPasteboard.PasteboardType.tiff.rawValue), let tiff = pasteboard.data(forType: .tiff) {
            return .image(tiff, isPNG: false)
        }
        return nil
    }
}
