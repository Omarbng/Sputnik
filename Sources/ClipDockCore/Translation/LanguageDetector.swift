import NaturalLanguage

/// Works out which language a text is in, and where it goes: French and Russian become
/// English, and English becomes Russian (or French, a setting).
public enum LanguageDetector {
    /// More than this share of Cyrillic letters means the text is Russian.
    public static let cyrillicThreshold = 0.3
    /// Latin text counts as French only when the recognizer is at least this sure, so short
    /// words that are the same in both languages ("menu") stay English.
    public static let frenchConfidence = 0.6
    /// Only the start of long texts is examined.
    static let sampleLength = 2_000

    /// A foreign text always goes into English. English goes into `englishTarget`.
    public static func direction(for text: String, englishTarget: TranslationLanguage = .russian) -> TranslationDirection {
        let source = language(of: text)
        guard source == .english else { return TranslationDirection(source, to: .english) }
        return TranslationDirection(.english, to: englishTarget == .english ? .russian : englishTarget)
    }

    /// The Cyrillic share decides Russian first. Otherwise `NLLanguageRecognizer`, limited to
    /// ClipDock's three languages, decides. Text it can't place (numbers, names) counts as English.
    public static func language(of text: String) -> TranslationLanguage {
        let sample = String(text.prefix(sampleLength))
        if let share = cyrillicShare(of: sample), share > cyrillicThreshold {
            return .russian
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .french, .russian]
        recognizer.processString(sample)
        guard let (best, confidence) = recognizer.languageHypotheses(withMaximum: 3).max(by: { $0.value < $1.value })
        else { return .english }
        switch best {
        case .russian: return .russian
        case .french where confidence >= frenchConfidence: return .french
        default: return .english
        }
    }

    /// The share of letters that are Cyrillic, or nil if the text has no letters.
    static func cyrillicShare(of text: String) -> Double? {
        var letters = 0
        var cyrillic = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if (0x0400...0x052F).contains(scalar.value) { cyrillic += 1 }  // Cyrillic + Supplement
        }
        return letters == 0 ? nil : Double(cyrillic) / Double(letters)
    }
}
