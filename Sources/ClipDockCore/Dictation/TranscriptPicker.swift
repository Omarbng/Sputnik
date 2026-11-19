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

/// Apple's recognisers can't tell which language was spoken, so ClipDock runs English and
/// Russian side by side and keeps the reading that fits. A recogniser hearing the wrong
/// language writes junk: little text, low confidence, or the wrong alphabet (an English
/// recogniser can't write Cyrillic; a Russian one writes Latin for English words).
public enum TranscriptPicker {
    public static func pick(_ candidates: [TranscriptCandidate]) -> TranscriptCandidate? {
        candidates
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func score(_ candidate: TranscriptCandidate) -> Double {
        let letters = candidate.text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let matching = letters.filter { scalar in
            switch candidate.language {
            case .russian: (0x0400...0x052F).contains(scalar.value)
            case .english, .french: scalar.isASCII || (0x00C0...0x024F).contains(scalar.value)
            }
        }
        let share = Double(matching.count) / Double(letters.count)
        // More readable letters mean more was understood; it levels off after a few words.
        let amount = min(Double(matching.count) / 12, 1)
        return (candidate.confidence ?? 0.5) * share * (0.5 + 0.5 * amount)
    }
}
