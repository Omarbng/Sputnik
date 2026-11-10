import ClipDockCore
import Foundation

/// UserDefaults-backed settings. The Settings window (M4) edits these; until then, defaults apply.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let maxUnpinnedItems = "maxUnpinnedItems"
        static let retentionDays = "retentionDays"
        static let didShowPasteAccessCard = "didShowPasteAccessCard"
        static let didShowAccessibilityCard = "didShowAccessibilityCard"
        static let didPromptAccessibility = "didPromptAccessibility"
        static let didShowLanguageCard = "didShowLanguageCard"
        static let pasteAllSeparator = "pasteAllSeparator"
        static let pausedUntil = "pausedUntil"
    }

    static var ignoredBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? SkipRules.defaultIgnoredBundleIDs }
        set { defaults.set(newValue, forKey: Key.ignoredBundleIDs) }
    }

    static var maxUnpinnedItems: Int {
        get { defaults.object(forKey: Key.maxUnpinnedItems) as? Int ?? RetentionPolicy().maxUnpinned }
        set { defaults.set(newValue, forKey: Key.maxUnpinnedItems) }
    }

    static var retentionDays: Int {
        get { defaults.object(forKey: Key.retentionDays) as? Int ?? RetentionPolicy().maxAgeDays }
        set { defaults.set(newValue, forKey: Key.retentionDays) }
    }

    static var retention: RetentionPolicy {
        RetentionPolicy(maxUnpinned: maxUnpinnedItems, maxAgeDays: retentionDays)
    }

    static var pasteAllSeparator: PasteAllSeparator {
        get { defaults.string(forKey: Key.pasteAllSeparator).flatMap(PasteAllSeparator.init(rawValue:)) ?? .newline }
        set { defaults.set(newValue.rawValue, forKey: Key.pasteAllSeparator) }
    }

    /// When paused capture resumes by itself. `.distantFuture` means "until resumed"; nil means
    /// not paused. Kept across relaunches, so a pause isn't silently lifted.
    static var pausedUntil: Date? {
        get { defaults.object(forKey: Key.pausedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.pausedUntil) }
    }

    static var didShowPasteAccessCard: Bool {
        get { defaults.bool(forKey: Key.didShowPasteAccessCard) }
        set { defaults.set(newValue, forKey: Key.didShowPasteAccessCard) }
    }

    static var didShowAccessibilityCard: Bool {
        get { defaults.bool(forKey: Key.didShowAccessibilityCard) }
        set { defaults.set(newValue, forKey: Key.didShowAccessibilityCard) }
    }

    static var didShowLanguageCard: Bool {
        get { defaults.bool(forKey: Key.didShowLanguageCard) }
        set { defaults.set(newValue, forKey: Key.didShowLanguageCard) }
    }

    /// macOS shows its Accessibility prompt only once per app; after that we open Settings.
    static var didPromptAccessibility: Bool {
        get { defaults.bool(forKey: Key.didPromptAccessibility) }
        set { defaults.set(newValue, forKey: Key.didPromptAccessibility) }
    }
}
