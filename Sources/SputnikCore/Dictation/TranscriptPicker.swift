import Foundation

/// One recogniser's reading of a dictation.
public struct TranscriptCandidate: Sendable, Equatable {
    public var language: TranslationLanguage
    public var text: String
    /// 0…1, averaged over the text; nil when the recogniser gave none.
    public var confidence: Double?

    public init(language: TranslationLanguage, text: String, confidence: Double?) {
        self.language = language
        self.text = text
        self.confidence = confidence
    }
}

/// Apple's recognisers can't tell which language was spoken, so Sputnik runs one per spoken
/// language side by side and keeps the reading that fits. A recogniser hearing the wrong
/// language writes junk: little text, low confidence, or the wrong alphabet (an English
/// recogniser can't write Cyrillic; a Russian one writes Latin for English words). Between two
/// languages with the same alphabet (English and German), the language of the text decides.
public enum TranscriptPicker {
    public static func pick(_ candidates: [TranscriptCandidate]) -> TranscriptCandidate? {
        candidates
            .map { ($0, score($0, among: candidates)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func score(_ candidate: TranscriptCandidate, among candidates: [TranscriptCandidate] = []) -> Double {
        let counts = Script.counts(in: candidate.text)
        let letters = counts.values.reduce(0, +)
        guard letters > 0 else { return 0 }
        let matching = counts.filter { $0.key.fits(candidate.language.script) }.values.reduce(0, +)
        let share = Double(matching) / Double(letters)
        // More readable letters mean more was understood; it levels off after a few words.
        let amount = min(Double(matching) / 12, 1)
        return (candidate.confidence ?? 0.5) * share * (0.5 + 0.5 * amount) * fit(candidate, among: candidates)
    }

    /// 1 unless another recogniser writes the same alphabet; then how likely the text is in
    /// this candidate's language rather than theirs.
    static func fit(_ candidate: TranscriptCandidate, among candidates: [TranscriptCandidate]) -> Double {
        let rivals = Set(candidates.map(\.language).filter { $0 != candidate.language && $0.script == candidate.language.script })
        guard !rivals.isEmpty, candidate.text.count >= 8 else { return 1 }
        let languages = [candidate.language] + Array(rivals)
        let best = LanguageDetector.language(of: candidate.text, among: languages, main: candidate.language)
        return best == candidate.language ? 1 : 0.5
    }
}
