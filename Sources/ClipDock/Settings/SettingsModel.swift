import AVFoundation
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
    /// The double-tap keys. Picking a key another one uses swaps them, so they never clash.
    var popupTap = AppSettings.popupTap {
        didSet {
            if popupTap != nil, popupTap == translateTap { translateTap = oldValue }
            if popupTap != nil, popupTap == proofreadTap { proofreadTap = oldValue }
            AppSettings.popupTap = popupTap
        }
    }
    var translateTap = AppSettings.translateTap {
        didSet {
            if translateTap != nil, translateTap == popupTap { popupTap = oldValue }
            if translateTap != nil, translateTap == proofreadTap { proofreadTap = oldValue }
            AppSettings.translateTap = translateTap
        }
    }
    var proofreadTap = AppSettings.proofreadTap {
        didSet {
            if proofreadTap != nil, proofreadTap == popupTap { popupTap = oldValue }
            if proofreadTap != nil, proofreadTap == translateTap { translateTap = oldValue }
            AppSettings.proofreadTap = proofreadTap
        }
    }

    var separator = AppSettings.pasteAllSeparator {
        didSet { AppSettings.pasteAllSeparator = separator }
    }
    private(set) var ignoredApps = AppSettings.ignoredBundleIDs {
        didSet { AppSettings.ignoredBundleIDs = ignoredApps }
    }

    /// The feature switches (all on unless turned off).
    private(set) var switches: [AppSettings.Switch: Bool] = [:]
    /// Main, other and spoken languages (shared with the first-launch setup).
    let languages = LanguagesModel()
    /// The personal dictionary, one word or name per line.
    var vocabulary = AppSettings.dictationVocabulary.joined(separator: "\n") {
        didSet {
            AppSettings.dictationVocabulary = vocabulary
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    private(set) var writingProblem: String?
    /// macOS's own use of fn ("Press 🌐 key to …"); nil when it does nothing.
    private(set) var fnKeyConflict: String?
    private(set) var wisprFlowRunning = false

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
        proofreadTap = AppSettings.proofreadTap
        switches = Dictionary(uniqueKeysWithValues: AppSettings.Switch.allCases.map { ($0, AppSettings.isOn($0)) })
        languages.reload()
        vocabulary = AppSettings.dictationVocabulary.joined(separator: "\n")
        limitsChanged = false
        refreshStatus(languagesMissing: languagesMissing)
    }

    func refreshStatus(languagesMissing: Bool) {
        launchAtLogin = LaunchAtLogin.isEnabled
        accessibilityGranted = AccessibilityAccess.isTrusted
        pasteAllowed = PasteboardAccess.behavior == .alwaysAllow
        languagesInstalled = !languagesMissing
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        writingProblem = WritingAssistant().unavailableReason
        fnKeyConflict = Self.fnKeyConflict()
        wisprFlowRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.hasPrefix("com.electron.wispr-flow") == true
        }
    }

    func isOn(_ setting: AppSettings.Switch) -> Bool {
        switches[setting] ?? AppSettings.isOn(setting)
    }

    func set(_ setting: AppSettings.Switch, _ on: Bool) {
        AppSettings.set(setting, on)
        switches[setting] = on
    }

    /// Asks once; after that macOS only lets Omar change it in System Settings.
    func allowMicrophone() {
        if microphone == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reads (never changes) the "Press 🌐 key to" setting.
    private static func fnKeyConflict() -> String? {
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int
        return switch value {
        case 0?: nil
        case 1?: "fn also changes the input source"
        case 2?: "fn also opens Emoji & Symbols"
        case 3?: "fn also starts Apple's dictation"
        default: "fn may also be used by macOS"
        }
    }

    func consumeLimitsChanged() -> Bool {
        defer { limitsChanged = false }
        return limitsChanged
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginMessage = LaunchAtLogin.needsApproval
                ? "Approve Sputnik in System Settings → General → Login Items."
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
