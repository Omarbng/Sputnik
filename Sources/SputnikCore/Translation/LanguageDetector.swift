import NaturalLanguage

/// Works out which of someone's languages a text is in, and where it goes: every other language
/// becomes the main one, and the main one becomes the target (Omar: Russian and French become
/// English; English becomes Russian, or French).
public enum LanguageDetector {
    /// More than this share of a non-Latin script's letters means the text is in that script
    /// (Russian text with a few English words is still Russian).
    public static let scriptThreshold = 0.3
    /// Same-script text counts as another language only when the recognizer is at least this
    /// sure, so short words that are the same in both ("menu") stay in the main language.
    public static let foreignConfidence = 0.6
    /// Only the start of long texts is examined.
    static let sampleLength = 2_000

    /// Omar's original rule, kept for the tests: main English, Russian and French.
    public static func direction(for text: String, englishTarget: TranslationLanguage = .russian) -> TranslationDirection {
        let setup = LanguageSetup(main: .english, others: [.russian, .french], target: englishTarget, spoken: [])
        return direction(for: text, setup: setup, target: englishTarget) ?? .englishToRussian
    }

    /// Another language goes into the main one. The main one goes into `target` (the reply
    /// language or the setup's target), or nil when there's nowhere to go.
    public static func direction(for text: String, setup: LanguageSetup, target: TranslationLanguage?) -> TranslationDirection? {
        let source = language(of: text, among: setup.all, main: setup.main)
        guard source == setup.main else { return TranslationDirection(source, to: setup.main) }
        guard let target, target != setup.main else { return nil }
        return TranslationDirection(setup.main, to: target)
    }

    /// Omar's original three: English (main), Russian and French.
    public static func language(of text: String) -> TranslationLanguage {
        language(of: text, among: [.english, .russian, .french], main: .english)
    }

    /// A distinctive script decides first (more than 30% Cyrillic → Russian when only Russian
    /// uses it). Otherwise `NLLanguageRecognizer`, limited to the languages written in that
    /// script, decides; a language other than the main one needs 60% confidence. Text it can't
    /// place (numbers, names) counts as the main language.
    public static func language(of text: String, among languages: [TranslationLanguage], main: TranslationLanguage) -> TranslationLanguage {
        let sample = String(text.prefix(sampleLength))
        let counts = Script.counts(in: sample)
        let letters = counts.values.reduce(0, +)
        guard letters > 0 else { return main }

        // The script the text is written in: a non-Latin one above the threshold, else Latin.
        let nonLatin = counts
            .filter { $0.key != .latin && Double($0.value) / Double(letters) > scriptThreshold }
            .max { $0.value < $1.value }?.key
        let script = nonLatin ?? .latin
        // Japanese is han plus kana: kana anywhere means Japanese, han alone may be Chinese.
        let fitting = languages.filter { candidate in
            if counts[.japanese, default: 0] > 0, candidate.script == .japanese { return true }
            return script.fits(candidate.script)
        }
        guard !fitting.isEmpty else { return main }
        if fitting.count == 1 { return fitting[0] }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = fitting.compactMap(\.nlLanguage)
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: fitting.count)
        guard let (best, confidence) = hypotheses.max(by: { $0.value < $1.value }),
              let language = fitting.first(where: { $0.nlLanguage == best })
        else { return fitting.contains(main) ? main : fitting[0] }
        if language != main, fitting.contains(main), confidence < foreignConfidence { return main }
        return language
    }

    /// The share of letters that are Cyrillic, or nil if the text has no letters.
    static func cyrillicShare(of text: String) -> Double? {
        let counts = Script.counts(in: text)
        let letters = counts.values.reduce(0, +)
        return letters == 0 ? nil : Double(counts[.cyrillic, default: 0]) / Double(letters)
    }
}

extension TranslationLanguage {
    /// The NaturalLanguage framework's name for it.
    var nlLanguage: NLLanguage? {
        switch code {
        case "zh": .simplifiedChinese
        case "zh-TW": .traditionalChinese
        default: NLLanguage(rawValue: code)
        }
    }
}
