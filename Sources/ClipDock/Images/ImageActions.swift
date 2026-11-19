import AppKit
import ClipDockCore

/// The image tools in the actions menu: Copy Text in Image, Paste Smaller Image, Copy as JPEG,
/// Remove Background. They work on copied images and on copied image files (HEIC photos).
/// New images they make are added to history, since they're what Omar now has.
@MainActor
final class ImageActions {
    private let database: HistoryDatabase
    private let capture: CaptureController
    private let paster: Paster
    private let hud: HUDController

    init(database: HistoryDatabase, capture: CaptureController, paster: Paster, hud: HUDController) {
        self.database = database
        self.capture = capture
        self.paster = paster
        self.hud = hud
    }

    /// The image's bytes: the stored PNG, or the copied file.
    func imageData(for item: ClipItem) -> Data? {
        if let blob = item.imageBlob { return try? Data(contentsOf: database.blobs.url(for: blob)) }
        if let path = item.imageFilePath { return try? Data(contentsOf: URL(fileURLWithPath: path)) }
        return nil
    }

    /// For ⌘T on an image: the text in it.
    func recognizedText(in item: ClipItem) async throws -> String {
        guard let data = imageData(for: item) else { throw ImageTools.Failure.unreadable }
        let started = ContinuousClock.now
        let text = try await ImageTools.recognizeText(in: data)
        Log.images.notice("text found id=\(item.id ?? -1, privacy: .public) chars=\(text.count, privacy: .public) ms=\(WritingAssistant.milliseconds(since: started), privacy: .public)")
        return text
    }

    func copyText(from item: ClipItem, closePopup: () -> Void) {
        closePopup()
        Task {
            hud.show("Reading text…", autoHide: false)
            do {
                let text = try await recognizedText(in: item)
                PasteboardWriter.write(text: text)
                record(.text(text, rtf: nil), like: item)
                hud.show("Text copied")
            } catch {
                hud.show(Self.message(for: error), style: .error)
            }
        }
    }

    func pasteSmaller(_ item: ClipItem, closePopup: () -> Void) {
        guard let data = imageData(for: item) else { return failed(closePopup) }
        do {
            let (jpeg, png) = try ImageTools.smaller(data)
            let pbItem = NSPasteboardItem()
            pbItem.setData(jpeg, forType: NSPasteboard.PasteboardType("public.jpeg"))
            pbItem.setData(png, forType: .png)
            PasteboardWriter.write([pbItem])
            closePopup()
            record(.image(png, isPNG: true), like: item)
            paster.pasteIntoFrontApp()
            Log.images.notice("smaller id=\(item.id ?? -1, privacy: .public) bytes=\(data.count, privacy: .public)->\(jpeg.count, privacy: .public)")
        } catch {
            failed(closePopup)
        }
    }

    /// Puts a JPEG on the clipboard both as image data and as a file (in ClipDock's own folder),
    /// so it pastes into chats and documents and also attaches or drops as a .jpg file.
    func copyAsJPEG(_ item: ClipItem, closePopup: () -> Void) {
        guard let data = imageData(for: item) else { return failed(closePopup) }
        do {
            let jpeg = try ImageTools.jpeg(data)
            let pbItem = NSPasteboardItem()
            pbItem.setData(jpeg, forType: NSPasteboard.PasteboardType("public.jpeg"))
            if let file = try? Self.export(jpeg, named: Self.baseName(for: item)) {
                pbItem.setString(file.absoluteString, forType: .fileURL)
            }
            PasteboardWriter.write([pbItem])
            closePopup()
            hud.show("Copied as JPEG")
            Log.images.notice("jpeg id=\(item.id ?? -1, privacy: .public) bytes=\(data.count, privacy: .public)->\(jpeg.count, privacy: .public)")
        } catch {
            failed(closePopup)
        }
    }

    func removeBackground(_ item: ClipItem, closePopup: () -> Void) {
        guard let data = imageData(for: item) else { return failed(closePopup) }
        closePopup()
        Task {
            hud.show("Removing background…", autoHide: false)
            do {
                let png = try await ImageTools.removeBackground(data)
                let pbItem = NSPasteboardItem()
                pbItem.setData(png, forType: .png)
                PasteboardWriter.write([pbItem])
                record(.image(png, isPNG: true), like: item)
                hud.show("Copied without the background")
                Log.images.notice("cutout id=\(item.id ?? -1, privacy: .public) bytes=\(png.count, privacy: .public)")
            } catch {
                hud.show(Self.message(for: error), style: .error)
            }
        }
    }

    /// Exported files live in ClipDock's folder and are removed after a day.
    static func exportDirectory() throws -> URL {
        let directory = try AppPaths.supportDirectory().appending(path: "exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func export(_ data: Data, named name: String) throws -> URL {
        let url = try exportDirectory().appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Deletes exports older than a day (run at launch).
    static func removeOldExports(now: Date = .now) {
        guard let directory = try? exportDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > 86_400 { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func baseName(for item: ClipItem) -> String {
        if let path = item.imageFilePath {
            return ((path as NSString).lastPathComponent as NSString).deletingPathExtension + ".jpg"
        }
        return "Image \(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")).jpg"
    }

    private func record(_ payload: ClipPayload, like item: ClipItem) {
        capture.record(CapturedClip(payload: payload, sourceBundleID: item.sourceBundleID, sourceAppName: item.sourceAppName, capturedAt: .now))
    }

    private func failed(_ closePopup: () -> Void) {
        closePopup()
        hud.show("Couldn't read that image", style: .error)
    }

    static func message(for error: Error) -> String {
        switch error as? ImageTools.Failure {
        case .noText?: "No text found in the image"
        case .noSubject?: "No clear subject to cut out"
        default: "Couldn't read that image"
        }
    }
}
