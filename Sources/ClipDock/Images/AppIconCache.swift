import AppKit

/// Source-app icons for rows, looked up once per bundle ID.
@MainActor
final class AppIconCache {
    private var icons: [String: NSImage] = [:]
    private var missing: Set<String> = []

    func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, !missing.contains(bundleID) else { return nil }
        if let icon = icons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = NSSize(width: 16, height: 16)
        icons[bundleID] = icon
        return icon
    }

    /// Looks icons up ahead of time so the first popup open doesn't pay for it.
    func warm(_ bundleIDs: [String?]) {
        for bundleID in Set(bundleIDs.compactMap { $0 }) {
            _ = icon(for: bundleID)
        }
    }
}
