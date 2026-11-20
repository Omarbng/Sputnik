import Foundation

/// Instant, rule-based clean-up of dictated text, for English and Russian:
/// - filler sounds go ("um", "uh" / "эм", "ээ")
/// - spoken layout becomes layout ("new line", "new paragraph" / "новая строка", "новый абзац")
/// - spacing is tidied and the first letter capitalised.
/// Apple's recogniser already adds punctuation; Apple Intelligence can polish further (English).
public enum DictationCleanup {
    /// Sounds that are never words. Meaningful fillers ("like", "ну", "типа") stay.
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "hm", "mm", "mmm", "ah",
        "эм", "эмм", "э", "ээ", "эээ", "мм", "ммм", "хм", "гм",
    ]

    static let layoutPhrases: [(phrase: String, replacement: String)] = [
        ("new paragraph", "\n\n"), ("новый абзац", "\n\n"), ("с нового абзаца", "\n\n"),
        ("new line", "\n"), ("next line", "\n"), ("новая строка", "\n"), ("с новой строки", "\n"),
    ]

    public static func clean(_ text: String) -> String {
        var result = removeFillers(text)
        result = applyLayout(result)
        result = tidySpacing(result)
        return capitalizeFirst(result)
    }

    /// Drops filler words together with a comma that follows them ("Um, so" → "so").
    static func removeFillers(_ text: String) -> String {
        var tokens: [String] = []
        var dropNextLeadingComma = false
        for raw in text.components(separatedBy: " ") {
            let core = raw.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if fillers.contains(core), !core.isEmpty {
                // Keep sentence-ending punctuation that was attached to the filler ("uh." → ".").
                if let last = raw.last, ".?!".contains(last), var previous = tokens.popLast() {
                    previous = previous.trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    tokens.append(previous + String(last))
                }
                dropNextLeadingComma = true
                continue
            }
            var token = raw
            if dropNextLeadingComma, token.hasPrefix(",") { token.removeFirst() }
            dropNextLeadingComma = false
            if !token.isEmpty { tokens.append(token) }
        }
        return tokens.joined(separator: " ")
    }

    /// "…today new line thanks" → "…today\nthanks". Punctuation the recogniser put around the
    /// phrase ("today. New line. Thanks") goes with it, apart from a sentence end before it.
    static func applyLayout(_ text: String) -> String {
        var result = text
        for (phrase, replacement) in layoutPhrases {
            let pattern = "[,;:]?\\s*\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b[.,;:!?]?\\s*"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        // Capitalise the first letter of each new line.
        let lines = result.components(separatedBy: "\n").map(capitalizeFirst)
        return lines.joined(separator: "\n")
    }

    static func tidySpacing(_ text: String) -> String {
        var result = text
        let rules: [(String, String)] = [
            ("[ \\t]+", " "),                 // runs of spaces
            (" +([,.;:!?])", "$1"),           // no space before punctuation
            ("([,;:])(?=[^\\s\\d])", "$1 "),  // a space after a comma (not inside 3,000)
            (" *\\n *", "\n"),                 // no spaces around line breaks
        ]
        for (pattern, template) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func capitalizeFirst(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        guard text[..<index].allSatisfy({ !$0.isLetter && !$0.isNumber }) else { return text }
        return text.replacingCharacters(in: index...index, with: text[index].uppercased())
    }
}
