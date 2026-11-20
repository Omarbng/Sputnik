import Foundation

/// What the Shortcuts window lists (menu bar → Shortcuts…). Built from the current settings, so
/// a changed double-tap key or a feature switched off shows as it really is.
public enum ShortcutGuide {
    public struct Row: Equatable, Sendable, Identifiable {
        /// Keycaps, in order ("⌃", "⌃" for a double tap).
        public let keys: [String]
        public let title: String
        public let detail: String?
        public var id: String { title }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public let title: String
        public let rows: [Row]
        public var id: String { title }
    }

    public struct Options: Sendable {
        public var popupTap: TapModifier?
        public var translateTap: TapModifier?
        public var proofreadTap: TapModifier?
        public var dictation: Bool
        public var rightOption: Bool
        public var sayLanguage: Bool
        public var voiceCommands: Bool
        public var englishTarget: TranslationLanguage

        public init(
            popupTap: TapModifier?, translateTap: TapModifier?, proofreadTap: TapModifier?,
            dictation: Bool, rightOption: Bool, sayLanguage: Bool, voiceCommands: Bool,
            englishTarget: TranslationLanguage
        ) {
            self.popupTap = popupTap
            self.translateTap = translateTap
            self.proofreadTap = proofreadTap
            self.dictation = dictation
            self.rightOption = rightOption
            self.sayLanguage = sayLanguage
            self.voiceCommands = voiceCommands
            self.englishTarget = englishTarget
        }
    }

    public static func sections(_ options: Options) -> [Section] {
        [voice(options), selection(options), clipboard(options)].filter { !$0.rows.isEmpty }
    }

    private static func voice(_ options: Options) -> Section {
        guard options.dictation else { return Section(title: "Talk", rows: []) }
        var rows = [
            Row(keys: ["fn"], title: "Hold fn and talk",
                detail: "Let go and it's typed where you are, in English or Russian."
                    + (options.rightOption ? " Holding right ⌥ works too." : "")),
            Row(keys: ["fn", "fn"], title: "Talk without holding",
                detail: "Tap fn twice. fn again finishes, esc cancels."),
            Row(keys: ["fn", "⇧"], title: "Talk in English, type in \(options.englishTarget.name)",
                detail: "Tap ⇧ once while talking (the dots turn blue). Russian comes out in English."),
        ]
        if options.sayLanguage {
            rows.append(Row(keys: ["fn", "⇧"], title: "Say the language first",
                            detail: "Start with “in French”, “in Russian” or “по-английски”. Those words aren't typed."))
        }
        if options.voiceCommands {
            rows.append(Row(keys: ["fn", "⌃"], title: "Change the selected text",
                            detail: "Tap ⌃ while talking (amber dots) and say “proofread”, “make it shorter”, “translate to French”, or anything else."))
            rows.append(Row(keys: ["fn"], title: "Paste a saved item by name",
                            detail: "Say “insert office address”."))
        }
        return Section(title: "Talk", rows: rows)
    }

    private static func selection(_ options: Options) -> Section {
        var rows: [Row] = []
        if let tap = options.translateTap {
            rows.append(Row(keys: [tap.symbol, tap.symbol], title: "Translate",
                            detail: "↩ replaces the text, ⌘C copies it. Nothing selected? It translates what you copied."))
        }
        if let tap = options.proofreadTap {
            rows.append(Row(keys: [tap.symbol, tap.symbol], title: "Proofread",
                            detail: "Fixes spelling and grammar in place. ⌘Z undoes it."))
        }
        return Section(title: "Selected text, in any app", rows: rows)
    }

    private static func clipboard(_ options: Options) -> Section {
        var rows: [Row] = []
        if let tap = options.popupTap {
            rows.append(Row(keys: [tap.symbol, tap.symbol], title: "Open clipboard history", detail: "Type to search."))
        }
        rows += [
            Row(keys: ["↩"], title: "Paste", detail: "⌘1 – ⌘9 pastes the first nine."),
            Row(keys: ["⌘", "K"], title: "Actions", detail: "Proofread, shorten, WhatsApp, call, text in an image, and more."),
            Row(keys: ["⇧", "Space"], title: "See the whole item", detail: "↑↓ for the next one."),
            Row(keys: ["⌘", "T"], title: "Translate the item", detail: "↩ pastes the translation."),
            Row(keys: ["Space", "⌘", "↩"], title: "Paste several together", detail: "Space marks items, ⌘↩ pastes them in that order."),
            Row(keys: ["⇧", "⌘", "↩"], title: "Paste marked items one by one", detail: "Each ⌘V, in any app, pastes the next."),
            Row(keys: ["⌘", "P"], title: "Save it", detail: "⌘L saves it as a secret instead (Touch ID to paste)."),
        ]
        return Section(title: "Clipboard", rows: rows)
    }
}
