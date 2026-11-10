import AppKit
import ClipDockCore
import Observation
import UniformTypeIdentifiers

/// What the Settings window shows and edits. Each change is saved right away, except that
/// new history limits are applied when the window closes, so stepping past a value by
/// mistake doesn't delete anything.
@MainActor
@Observable
final class SettingsModel {
    var maxItems = AppSettings.maxUnpinnedItems {
        didSet { AppSettings.maxUnpinnedItems = maxItems; limitsChanged = true }
    }
    var retentionDays = AppSettings.retentionDays {
        didSet { AppSettings.retentionDays = retentionDays; limitsChanged = true }
    }
    /// The double-tap keys. Picking the other one's key swaps them, so they never clash.
    var popupTap = AppSettings.popupTap {
        didSet {
            if popupTap != nil, popupTap == translateTap { translateTap = oldValue }
            AppSettings.popupTap = popupTap
        }
    }
    var translateTap = AppSettings.translateTap {
        didSet {
            if translateTap != nil, translateTap == popupTap { popupTap = oldValue }
            AppSettings.translateTap = translateTap
        }
    }

    var separator = AppSettings.pasteAllSeparator {
        didSet { AppSettings.pasteAllSeparator = separator }
    }
    private(set) var ignoredApps = AppSettings.ignoredBundleIDs {
        didSet { AppSettings.ignoredBundleIDs = ignoredApps }
    }

    private(set) var launchAtLogin = LaunchAtLogin.isEnabled
    private(set) var launchAtLoginMessage: String?
    private(set) var accessibilityGranted = AccessibilityAccess.isTrusted
    private(set) var pasteAllowed = PasteboardAccess.behavior == .alwaysAllow
    private(set) var languagesInstalled = true

    @ObservationIgnored private(set) var limitsChanged = false

    /// Re-reads everything, for when the window opens.
    func reload(languagesMissing: Bool) {
        maxItems = AppSettings.maxUnpinnedItems
        retentionDays = AppSettings.retentionDays
        separator = AppSettings.pasteAllSeparator
        ignoredApps = AppSettings.ignoredBundleIDs
        popupTap = AppSettings.popupTap
        translateTap = AppSettings.translateTap
        limitsChanged = false
        refreshStatus(languagesMissing: languagesMissing)
    }

    func refreshStatus(languagesMissing: Bool) {
        launchAtLogin = LaunchAtLogin.isEnabled
        accessibilityGranted = AccessibilityAccess.isTrusted
        pasteAllowed = PasteboardAccess.behavior == .alwaysAllow
        languagesInstalled = !languagesMissing
    }

    func consumeLimitsChanged() -> Bool {
        defer { limitsChanged = false }
        return limitsChanged
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginMessage = LaunchAtLogin.needsApproval
                ? "Approve ClipDock in System Settings → General → Login Items."
                : nil
        } catch {
            launchAtLoginMessage = "macOS didn't allow it: \(error.localizedDescription)"
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Lets Omar pick an app; its bundle ID joins the ignored list.
    func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !ignoredApps.contains(bundleID)
        else { return }
        ignoredApps.append(bundleID)
    }

    func removeIgnoredApp(_ bundleID: String) {
        ignoredApps.removeAll { $0 == bundleID }
    }

    func restoreDefaultIgnoredApps() {
        ignoredApps = SkipRules.defaultIgnoredBundleIDs
    }

    /// The app's name, or nil if it isn't installed.
    static func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")
    }
}
