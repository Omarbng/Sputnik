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
        /// Renamed when French was added (2026-11-18), so the card offers that download once.
        static let didShowLanguageCard = "didShowLanguageCard.french"
        static let englishTarget = "translateEnglishInto"
        static let pasteAllSeparator = "pasteAllSeparator"
        static let pausedUntil = "pausedUntil"
        static let popupTap = "popupDoubleTap"
        static let translateTap = "translateDoubleTap"
        static let proofreadTap = "proofreadDoubleTap"
        static let didMigrateToDoubleTaps = "didMigrateToDoubleTaps"
        // Switches added 2026-11-19 (all on by default).
        static let translateClipboard = "translateClipboardWhenNothingSelected"
        static let replyInTheirLanguage = "replyInTheirLanguage"
        static let cleanLinks = "cleanTrackingFromLinks"
        static let expireSensitive = "forgetSensitiveCopies"
        static let writingTools = "writingActions"
        static let dictation = "dictationHoldFn"
        static let dictationLanguage = "dictationLanguage"
        static let dictationRules = "dictationRemoveFillers"
        static let dictationPolish = "dictationPolishWithAppleIntelligence"
        static let voiceCommands = "dictationVoiceCommands"
        static let dictationVocabulary = "dictationVocabulary"
        // Added 2026-11-20 ("make it easier").
        static let rightOptionTalk = "dictationHoldRightOption"
        static let sayLanguage = "dictationSayLanguageFirst"
        // Added 2026-11-20 (Sputnik: anyone's languages, first-launch setup).
        static let languages = "languageSetup"
        static let didCompleteSetup = "didCompleteSetup"
    }

    /// The on/off switches in Settings. Each is on unless Omar turns it off.
    enum Switch: String, CaseIterable {
        /// ⌃⌃ with nothing selected translates what's on the clipboard.
        case translateClipboard
        /// After translating French or Russian, English goes back into that language for an hour.
        case replyInTheirLanguage
        /// Copied links lose `utm_…`, `fbclid` and the like.
        case cleanLinks
        /// Keys, card numbers, IBANs and one-time codes leave history after 10 minutes.
        case expireSensitive
        /// Proofread, Make Professional, Shorter, Summarize in ⌘K (Apple Intelligence).
        case writingTools
        /// Hold fn to dictate.
        case dictation
        /// Remove "um", "uh" / "эм" and turn "new line" into a line break.
        case dictationRules
        /// Polish dictation (English and Russian) with Apple Intelligence.
        case dictationPolish
        /// fn+⌃ commands, and "insert <saved item>" while dictating.
        case voiceCommands
        /// Holding right ⌥ works like holding fn.
        case rightOptionTalk
        /// fn+⇧ that starts with "in French" / "по-английски" translates into that language.
        case sayLanguage

        var key: String {
            switch self {
            case .translateClipboard: Key.translateClipboard
            case .replyInTheirLanguage: Key.replyInTheirLanguage
            case .cleanLinks: Key.cleanLinks
            case .expireSensitive: Key.expireSensitive
            case .writingTools: Key.writingTools
            case .dictation: Key.dictation
            case .dictationRules: Key.dictationRules
            case .dictationPolish: Key.dictationPolish
            case .voiceCommands: Key.voiceCommands
            case .rightOptionTalk: Key.rightOptionTalk
            case .sayLanguage: Key.sayLanguage
            }
        }
    }

    static func isOn(_ setting: Switch) -> Bool {
        defaults.object(forKey: setting.key) as? Bool ?? true
    }

    static func set(_ setting: Switch, _ on: Bool) {
        defaults.set(on, forKey: setting.key)
    }

    /// The languages this person works in (chosen in the setup or Settings). Until then, a
    /// guess from the Mac's own language.
    static var languages: LanguageSetup {
        get {
            if let data = defaults.data(forKey: Key.languages),
               let setup = try? JSONDecoder().decode(LanguageSetup.self, from: data) {
                return setup
            }
            return .suggested(preferredLanguages: Locale.preferredLanguages)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Key.languages) }
        }
    }

    /// Names and words the recogniser should expect (the personal dictionary), one per line.
    static var dictationVocabulary: [String] {
        get { defaults.stringArray(forKey: Key.dictationVocabulary) ?? [] }
        set { defaults.set(newValue, forKey: Key.dictationVocabulary) }
    }

    /// The first-launch setup ran (or this Mac used ClipDock before the setup existed).
    static var didCompleteSetup: Bool {
        get { defaults.bool(forKey: Key.didCompleteSetup) }
        set { defaults.set(newValue, forKey: Key.didCompleteSetup) }
    }

    /// Once, at launch: a Mac that ran ClipDock keeps its languages (English into Russian or
    /// French, dictation from the old picker) and skips the setup.
    static func migrateFromClipDockOnce() {
        guard defaults.data(forKey: Key.languages) == nil else { return }
        let legacy = [Key.didShowPasteAccessCard, Key.didShowAccessibilityCard, Key.englishTarget, Key.dictationLanguage, Key.popupTap]
        guard legacy.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        languages = .migrated(
            englishTarget: defaults.string(forKey: Key.englishTarget),
            dictation: defaults.string(forKey: Key.dictationLanguage)
        )
        didCompleteSetup = true
    }

    /// The modifier to double-tap to open the clipboard (default ⌥), or nil for off.
    static var popupTap: TapModifier? {
        get { tapSetting(Key.popupTap, default: .option) }
        set { defaults.set(newValue?.rawValue ?? "off", forKey: Key.popupTap) }
    }

    /// The modifier to double-tap to translate the selected text (default ⌃), or nil for off.
    static var translateTap: TapModifier? {
        get { tapSetting(Key.translateTap, default: .control) }
        set { defaults.set(newValue?.rawValue ?? "off", forKey: Key.translateTap) }
    }

    /// The modifier to double-tap to proofread the selected text in place (default ⇧), or nil.
    static var proofreadTap: TapModifier? {
        get { tapSetting(Key.proofreadTap, default: .shift) }
        set { defaults.set(newValue?.rawValue ?? "off", forKey: Key.proofreadTap) }
    }

    private static func tapSetting(_ key: String, default fallback: TapModifier) -> TapModifier? {
        guard let raw = defaults.string(forKey: key) else { return fallback }
        return TapModifier(rawValue: raw)  // "off" → nil
    }

    /// One-time cleanup: the old combo shortcuts (⌘⇧V, ⌥⌘T, ⇧⌥⌘T) were stored by
    /// KeyboardShortcuts. Omar replaced them with double-taps on 2026-11-11.
    static func removeOldComboShortcutsOnce() {
        guard !defaults.bool(forKey: Key.didMigrateToDoubleTaps) else { return }
        for name in ["openPopup", "translateInPlace", "translateShowOnly"] {
            defaults.removeObject(forKey: "KeyboardShortcuts_" + name)
        }
        defaults.set(true, forKey: Key.didMigrateToDoubleTaps)
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
