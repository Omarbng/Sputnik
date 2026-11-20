import Foundation

/// Which languages someone works in, chosen in the first-launch setup or Settings:
/// - `main`: the language they write in; everything else translates into it.
/// - `others`: languages they read or write besides it.
/// - `target`: where text in the main language goes (one of `others`), unless "Reply in their
///   language" remembers the conversation's language.
/// - `spoken`: what dictation listens for (a few at most: each one is a recogniser running).
public struct LanguageSetup: Equatable, Sendable, Codable {
    public private(set) var main: TranslationLanguage
    public private(set) var others: [TranslationLanguage]
    public private(set) var target: TranslationLanguage?
    public private(set) var spoken: [TranslationLanguage]

    /// Dictation runs one recogniser per spoken language, all at once.
    public static let maxSpoken = 3

    public init(main: TranslationLanguage, others: [TranslationLanguage], target: TranslationLanguage?, spoken: [TranslationLanguage]) {
        self.main = main
        self.others = others
        self.target = target
        self.spoken = spoken
        normalize()
    }

    /// Omar's languages: English, translating into Russian (or French); dictation in both.
    public static let omar = LanguageSetup(main: .english, others: [.russian, .french], target: .russian, spoken: [.english, .russian])

    /// The main language first, then the others.
    public var all: [TranslationLanguage] { [main] + others }

    /// Every direction translation uses: each other language into the main one, and back.
    public var directions: [TranslationDirection] {
        others.flatMap { [TranslationDirection($0, to: main), TranslationDirection(main, to: $0)] }
    }

    public mutating func setMain(_ language: TranslationLanguage) {
        if language != main, !others.contains(main) { others.insert(main, at: 0) }
        main = language
        normalize()
    }

    public mutating func setOthers(_ languages: [TranslationLanguage]) {
        others = languages
        normalize()
    }

    public mutating func setTarget(_ language: TranslationLanguage?) {
        target = language
        normalize()
    }

    public mutating func setSpoken(_ languages: [TranslationLanguage]) {
        spoken = languages
        normalize()
    }

    /// No duplicates, the main language never among the others, the target one of the others,
    /// and spoken languages among the chosen ones (at most `maxSpoken`).
    private mutating func normalize() {
        var seen: Set<TranslationLanguage> = [main]
        others = others.filter { seen.insert($0).inserted }
        if let target, !others.contains(target) { self.target = nil }
        if target == nil { target = others.first }
        var spokenSeen: Set<TranslationLanguage> = []
        spoken = Array(spoken.filter { all.contains($0) && spokenSeen.insert($0).inserted }.prefix(Self.maxSpoken))
    }

    // MARK: Starting points

    /// What someone upgrading from ClipDock had: English into Russian or French, and dictation
    /// "automatic" (English and Russian), "english" or "russian".
    public static func migrated(englishTarget: String?, dictation: String?) -> LanguageSetup {
        let target = englishTarget.flatMap(TranslationLanguage.init(rawValue:)).flatMap { [.russian, .french].contains($0) ? $0 : nil } ?? .russian
        let spoken: [TranslationLanguage] = switch dictation {
        case "english": [.english]
        case "russian": [.russian]
        default: [.english, .russian]
        }
        return LanguageSetup(main: .english, others: [.russian, .french], target: target, spoken: spoken)
    }

    /// A first guess for a new user, from the Mac's language: that language as the main one
    /// (English if Apple can't translate it), English as the other when the main one isn't.
    public static func suggested(preferredLanguages: [String]) -> LanguageSetup {
        let main = preferredLanguages.lazy.compactMap(Self.catalogLanguage(for:)).first ?? .english
        let others: [TranslationLanguage] = main == .english ? [] : [.english]
        return LanguageSetup(main: main, others: others, target: nil, spoken: [main])
    }

    /// The catalog language for a system language code ("en-GB" → English, "zh-Hant-TW" →
    /// Chinese (Traditional), "pt-BR" → Portuguese).
    public static func catalogLanguage(for identifier: String) -> TranslationLanguage? {
        let lowered = identifier.lowercased()
        if lowered.hasPrefix("zh") {
            return lowered.contains("hant") || lowered.hasSuffix("tw") || lowered.hasSuffix("hk") ? .chineseTraditional : .chinese
        }
        let base = String(lowered.prefix { $0 != "-" && $0 != "_" })
        return TranslationLanguage.catalog.first { $0.code == base }
    }
}
