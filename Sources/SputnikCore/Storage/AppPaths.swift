import Foundation

public enum AppPaths {
    /// ~/Library/Application Support/ClipDock (the app's name before 2026-11-20; kept so
    /// existing history carries over)
    public static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appending(path: "ClipDock", directoryHint: .isDirectory)
    }
}
