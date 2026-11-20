import Foundation

/// Recognising a language named out loud: "German", "Deutsch", "немецкий", "по-немецки".
extension TranslationLanguage {
    /// The language a spoken word names, or nil. `neighbours` are the words around it, for
    /// "traditional chinese".
    static func named(_ word: String, near neighbours: [String] = []) -> TranslationLanguage? {
        let word = word.lowercased()
        guard word.count >= 4 else { return nil }
        if word.hasPrefix("chinese") || word.hasPrefix("китайск") {
            return neighbours.contains { $0.hasPrefix("tradition") || $0.hasPrefix("традицион") } ? .chineseTraditional : .chinese
        }
        for language in catalog {
            if word.hasPrefix(language.name.lowercased()) { return language }
            if let native = language.nativeName.lowercased().split(separator: " ").first, native.count >= 4, word.hasPrefix(native) {
                return language
            }
            if language.russianStems.contains(where: { word.hasPrefix($0) }) { return language }
        }
        return nil
    }

    /// The first language named in a list of spoken words.
    static func named(in words: [String]) -> TranslationLanguage? {
        for (index, word) in words.enumerated() {
            let neighbours = Array(words[max(0, index - 1)...min(words.count - 1, index + 1)])
            if let language = named(word, near: neighbours) { return language }
        }
        return nil
    }

    /// Regex alternatives for English lead-ins: "arabic|german|…|chinese".
    static var englishNamePattern: String {
        var seen: [String] = []
        for language in catalog {
            let first = String(language.name.lowercased().prefix { $0 != " " })
            if !seen.contains(first) { seen.append(first) }
        }
        return seen.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }

    /// Regex alternatives for Russian lead-ins: "арабск|немецк|…".
    static var russianStemPattern: String {
        catalog.flatMap(\.russianStems).joined(separator: "|")
    }
}
