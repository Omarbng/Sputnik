import Foundation

/// fn + ⇧ with the language said first: "In French, see you tomorrow" or
/// "По-английски: увидимся завтра". The lead-in picks the language for this one translation
/// and isn't typed. Without one, the usual direction applies (Russian → English, English →
/// the reply language or Settings').
public enum SpokenLanguage {
    public struct Split: Equatable, Sendable {
        public let language: TranslationLanguage
        /// What was said after the lead-in, first letter capitalised. Empty when only the
        /// language was said.
        public let rest: String
    }

    // "in French", "translate to German", "translate into English" (any language Apple
    // translates), optionally followed by a comma, colon, dash or full stop. A bare "to French …"
    // is too often an ordinary sentence.
    private static let englishLeadIn = try! NSRegularExpression(
        pattern: #"^\s*(?:in|(?:please\s+)?translate\s+(?:in|into|to))\s+((?:traditional\s+|simplified\s+)?(?:"#
            + TranslationLanguage.englishNamePattern + #"))(?!\p{L})[\s,.:;!\-–—]*"#,
        options: [.caseInsensitive]
    )
    // "по-французски", "по немецки", "на русском", "на английский", "переведи на испанский".
    private static let russianLeadIn = try! NSRegularExpression(
        pattern: #"^\s*(?:переведи(?:те)?\s+)?(?:по[\s\-‐]*((?:"# + TranslationLanguage.russianStemPattern
            + #")и)|на\s+((?:"# + TranslationLanguage.russianStemPattern + #")\p{L}*))(?!\p{L})[\s,.:;!\-–—]*"#,
        options: [.caseInsensitive]
    )

    /// The language said first and the rest, or nil when the text doesn't start with one. A
    /// lead-in naming the language the rest is already in isn't one ("In English we say…",
    /// "На русском рынке…").
    public static func split(_ text: String) -> Split? {
        let whole = NSRange(text.startIndex..., in: text)
        for regex in [englishLeadIn, russianLeadIn] {
            guard let match = regex.firstMatch(in: text, range: whole),
                  let language = language(in: match, of: text),
                  let end = Range(match.range, in: text)?.upperBound
            else { continue }
            let rest = text[end...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty, LanguageDetector.language(of: rest, among: TranslationLanguage.catalog, main: language) == language { return nil }
            return Split(language: language, rest: rest.prefix(1).uppercased() + rest.dropFirst())
        }
        return nil
    }

    private static func language(in match: NSTextCheckingResult, of text: String) -> TranslationLanguage? {
        for group in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: group), in: text) else { continue }
            let words = text[range].lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            if let language = TranslationLanguage.named(in: words) { return language }
        }
        return nil
    }
}
