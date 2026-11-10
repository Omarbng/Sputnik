import Foundation
@testable import ClipDockCore

/// An in-memory history with a throwaway blob folder, removed when the test ends.
final class TemporaryHistory {
    let blobDirectory: URL
    let database: HistoryDatabase

    init() throws {
        blobDirectory = FileManager.default.temporaryDirectory
            .appending(path: "ClipDockTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        database = try .inMemory(blobDirectory: blobDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: blobDirectory)
    }

    func blobFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: blobDirectory.path(percentEncoded: false))
    }
}

/// A fixed "now" so tests don't depend on the real clock.
let referenceNow = Date(timeIntervalSince1970: 1_800_000_000)

func daysAgo(_ days: Double, from now: Date = referenceNow) -> Date {
    now.addingTimeInterval(-days * 86_400)
}

func textClip(_ text: String, at date: Date = referenceNow, app: String = "com.apple.TextEdit") -> CapturedClip {
    CapturedClip(payload: .text(text, rtf: nil), sourceBundleID: app, sourceAppName: app, capturedAt: date)
}

/// A tiny valid PNG (1×1), varied by `seed` so different seeds hash differently.
func pngClip(seed: UInt8, at date: Date = referenceNow) -> CapturedClip {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    bytes.append(seed)
    return CapturedClip(payload: .image(Data(bytes), isPNG: true), sourceBundleID: nil, sourceAppName: nil, capturedAt: date)
}
