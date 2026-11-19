import Foundation

/// What a spoken instruction asks for (fn + ⌃, or "insert …" in plain dictation).
public enum VoiceCommand: Sendable, Equatable {
    /// "insert office address" / "вставь адрес офиса": paste the saved item with that name.
    case insertSaved(name: String)
    /// "translate to Russian" / "переведи на английский".
    case translate(to: TranslationLanguage)
    /// "proofread", "make it shorter", "сделай официальнее" …
    case rewrite(RewriteStyle)
    /// Anything else, handed to Apple Intelligence as an editing instruction.
    case freeform(String)

    static let insertVerbs = ["insert", "paste", "type", "вставь", "вставить", "вставьте", "напиши"]

    /// The saved item's name in "insert <name>", or nil when it isn't that kind of command.
    public static func snippetName(in spoken: String) -> String? {
        let words = normalizedWords(spoken)
        guard words.count >= 2, insertVerbs.contains(words[0]) else { return nil }
        var rest = Array(words.dropFirst())
        if ["my", "the", "мой", "мою", "моё", "мои"].contains(rest.first ?? ""), rest.count > 1 { rest.removeFirst() }
        return rest.joined(separator: " ")
    }

    /// Reads an instruction for selected text.
    public static func parse(_ spoken: String) -> VoiceCommand {
        let words = normalizedWords(spoken)
        let phrase = words.joined(separator: " ")
        if let name = snippetName(in: spoken) { return .insertSaved(name: name) }
        if words.contains(where: { $0.hasPrefix("translat") || $0.hasPrefix("перев") }) {
            if let language = language(in: words) { return .translate(to: language) }
        }
        let rewrites: [(keys: [String], style: RewriteStyle)] = [
            (["proofread", "fix", "correct", "grammar", "spelling", "исправь", "проверь", "ошибки"], .proofread),
            (["professional", "formal", "business", "polite", "официальн", "деловым", "вежлив"], .professional),
            (["friendly", "casual", "warm", "дружелюб", "теплее", "проще"], .friendly),
            (["summar", "tl dr", "tldr", "кратко изложи", "резюме", "суть"], .summarize),
            (["shorter", "shorten", "concise", "brief", "короче", "сократи", "покороче"], .shorter),
        ]
        for (keys, style) in rewrites where keys.contains(where: { phrase.contains($0) }) {
            return .rewrite(style)
        }
        return .freeform(spoken.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func language(in words: [String]) -> TranslationLanguage? {
        for word in words {
            if word.hasPrefix("russian") || word.hasPrefix("русск") { return .russian }
            if word.hasPrefix("english") || word.hasPrefix("английск") { return .english }
            if word.hasPrefix("french") || word.hasPrefix("француз") { return .french }
        }
        return nil
    }

    /// Lowercased words without punctuation ("Insert, my Office address." → insert my office address).
    static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’")).inverted)
            .filter { !$0.isEmpty }
    }
}

/// Finds the saved item Omar named out loud. Names are compared without case or punctuation;
/// an exact match wins, then a name that contains every spoken word, then the closest spelling
/// (the recogniser can split words wrongly: "test snippet" heard as "tests nippid").
public enum SavedNameMatcher {
    /// How alike the letters must be for a near match (1 = identical).
    static let minimumSimilarity = 0.75

    public static func match(spoken: String, names: [String]) -> Int? {
        let wanted = VoiceCommand.normalizedWords(spoken)
        guard !wanted.isEmpty else { return nil }
        let normalized = names.map(VoiceCommand.normalizedWords)
        if let exact = normalized.firstIndex(of: wanted) { return exact }
        let candidates = normalized.indices.filter { index in
            wanted.allSatisfy { word in normalized[index].contains { $0.hasPrefix(word) || word.hasPrefix($0) } }
        }
        // The shortest name that covers every word is the most specific match.
        if let best = candidates.min(by: { normalized[$0].count < normalized[$1].count }) { return best }
        let spokenLetters = wanted.joined()
        let scored = normalized.indices
            .map { ($0, similarity(spokenLetters, normalized[$0].joined())) }
            .filter { $0.1 >= minimumSimilarity }
        return scored.max { $0.1 < $1.1 }?.0
    }

    /// 1 − edit distance ÷ the longer length.
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        let distance = a.isEmpty ? b.count : previous[b.count]
        return 1 - Double(distance) / Double(max(a.count, b.count))
    }
}
