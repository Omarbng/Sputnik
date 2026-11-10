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
    }

    static var ignoredBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? SkipRules.defaultIgnoredBundleIDs }
        set { defaults.set(newValue, forKey: Key.ignoredBundleIDs) }
    }

    static var retention: RetentionPolicy {
        let defaultPolicy = RetentionPolicy()
        return RetentionPolicy(
            maxUnpinned: defaults.object(forKey: Key.maxUnpinnedItems) as? Int ?? defaultPolicy.maxUnpinned,
            maxAgeDays: defaults.object(forKey: Key.retentionDays) as? Int ?? defaultPolicy.maxAgeDays
        )
    }

    static var didShowPasteAccessCard: Bool {
        get { defaults.bool(forKey: Key.didShowPasteAccessCard) }
        set { defaults.set(newValue, forKey: Key.didShowPasteAccessCard) }
    }
}
