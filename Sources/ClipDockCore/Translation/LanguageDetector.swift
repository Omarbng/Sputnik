import NaturalLanguage

/// Russian text becomes English; everything else becomes Russian.
public enum LanguageDetector {
    /// More than this share of Cyrillic letters means the text is Russian.
    public static let cyrillicThreshold = 0.3
    /// Only the start of long texts is examined.
    static let sampleLength = 2_000

    public static func direction(for text: String) -> TranslationDirection {
        isRussian(text) ? .russianToEnglish : .englishToRussian
    }

    /// The Cyrillic share decides first. Otherwise `NLLanguageRecognizer` gets the final say.
    public static func isRussian(_ text: String) -> Bool {
        let sample = String(text.prefix(sampleLength))
        if let share = cyrillicShare(of: sample), share > cyrillicThreshold {
            return true
        }
        return NLLanguageRecognizer.dominantLanguage(for: sample) == .russian
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
