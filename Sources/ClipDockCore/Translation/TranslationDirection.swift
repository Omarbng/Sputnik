import Foundation

/// A language Sputnik translates (and, where Apple has a recogniser, dictates), by the code
/// Apple's engines use: "en", "ru", "zh-TW". Any language in `catalog` works; English, Russian
/// and French were the first three (Omar's).
public struct TranslationLanguage: Hashable, Sendable, Codable, RawRepresentable, Identifiable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    init(_ code: String) { rawValue = code }

    public var id: String { rawValue }
    /// The BCP 47 code, as used by `Locale.Language(identifier:)`.
    public var code: String { rawValue }
    /// "EN", "RU", "ZH-TW", for the translation card.
    public var shortName: String { rawValue.uppercased() }
    /// "Russian", in English.
    public var name: String { Self.info[rawValue]?.name ?? Locale(identifier: "en").localizedString(forIdentifier: rawValue) ?? rawValue }
    /// "Русский", in the language itself.
    public var nativeName: String { Self.info[rawValue]?.native ?? name }
    /// The alphabet it's written in, for telling languages apart.
    public var script: Script { Self.info[rawValue]?.script ?? .latin }
    /// Russian word stems for "translate to …" / "по-…" ("немецк" → немецкий, по-немецки).
    var russianStems: [String] { Self.info[rawValue]?.russian ?? [] }

    public static let english = TranslationLanguage("en")
    public static let russian = TranslationLanguage("ru")
    public static let french = TranslationLanguage("fr")
    public static let german = TranslationLanguage("de")
    public static let spanish = TranslationLanguage("es")
    public static let ukrainian = TranslationLanguage("uk")
    public static let japanese = TranslationLanguage("ja")
    public static let chinese = TranslationLanguage("zh")
    public static let chineseTraditional = TranslationLanguage("zh-TW")

    /// Every language Apple's on-device translation offers (macOS 26), by English name.
    public static let catalog: [TranslationLanguage] = info.keys
        .map(TranslationLanguage.init)
        .sorted { $0.name < $1.name }

    private struct Info {
        let name: String
        let native: String
        let script: Script
        let russian: [String]
    }

    private static let info: [String: Info] = [
        "ar": Info(name: "Arabic", native: "العربية", script: .arabic, russian: ["арабск"]),
        "de": Info(name: "German", native: "Deutsch", script: .latin, russian: ["немецк"]),
        "en": Info(name: "English", native: "English", script: .latin, russian: ["английск"]),
        "es": Info(name: "Spanish", native: "Español", script: .latin, russian: ["испанск"]),
        "fr": Info(name: "French", native: "Français", script: .latin, russian: ["французск", "француз"]),
        "hi": Info(name: "Hindi", native: "हिन्दी", script: .devanagari, russian: ["хинди"]),
        "id": Info(name: "Indonesian", native: "Bahasa Indonesia", script: .latin, russian: ["индонезийск"]),
        "it": Info(name: "Italian", native: "Italiano", script: .latin, russian: ["итальянск"]),
        "ja": Info(name: "Japanese", native: "日本語", script: .japanese, russian: ["японск"]),
        "ko": Info(name: "Korean", native: "한국어", script: .hangul, russian: ["корейск"]),
        "nl": Info(name: "Dutch", native: "Nederlands", script: .latin, russian: ["нидерландск", "голландск"]),
        "pl": Info(name: "Polish", native: "Polski", script: .latin, russian: ["польск"]),
        "pt": Info(name: "Portuguese", native: "Português", script: .latin, russian: ["португальск"]),
        "ru": Info(name: "Russian", native: "Русский", script: .cyrillic, russian: ["русск"]),
        "th": Info(name: "Thai", native: "ไทย", script: .thai, russian: ["тайск"]),
        "tr": Info(name: "Turkish", native: "Türkçe", script: .latin, russian: ["турецк"]),
        "uk": Info(name: "Ukrainian", native: "Українська", script: .cyrillic, russian: ["украинск"]),
        "vi": Info(name: "Vietnamese", native: "Tiếng Việt", script: .latin, russian: ["вьетнамск"]),
        "zh": Info(name: "Chinese (Simplified)", native: "简体中文", script: .han, russian: ["китайск"]),
        "zh-TW": Info(name: "Chinese (Traditional)", native: "繁體中文", script: .han, russian: []),
    ]
}

/// Writing systems, for telling languages apart by their letters.
public enum Script: String, Sendable {
    case latin, cyrillic, arabic, devanagari, thai, hangul, han
    /// Japanese mixes kana with han.
    case japanese

    /// The script of one character, or nil for digits, punctuation and symbols.
    public static func of(_ scalar: Unicode.Scalar) -> Script? {
        guard scalar.properties.isAlphabetic else { return nil }
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x1E00...0x1EFF: return .latin
        case 0x0400...0x052F: return .cyrillic
        case 0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return .arabic
        case 0x0900...0x097F: return .devanagari
        case 0x0E00...0x0E7F: return .thai
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return .hangul
        case 0x3040...0x30FF: return .japanese
        case 0x3400...0x4DBF, 0x4E00...0x9FFF: return .han
        default: return nil
        }
    }

    /// How many letters of `text` are in each script.
    public static func counts(in text: String) -> [Script: Int] {
        var counts: [Script: Int] = [:]
        for scalar in text.unicodeScalars {
            if let script = of(scalar) { counts[script, default: 0] += 1 }
        }
        return counts
    }

    /// Whether a letter of this script can belong to a language written in `script`
    /// (Japanese text also uses han).
    func fits(_ script: Script) -> Bool {
        self == script || (script == .japanese && self == .han)
    }
}

public struct TranslationDirection: Hashable, Sendable {
    public let source: TranslationLanguage
    public let target: TranslationLanguage

    public init(_ source: TranslationLanguage, to target: TranslationLanguage) {
        self.source = source
        self.target = target
    }

    public static let englishToRussian = TranslationDirection(.english, to: .russian)
    public static let russianToEnglish = TranslationDirection(.russian, to: .english)
    public static let frenchToEnglish = TranslationDirection(.french, to: .english)
    public static let englishToFrench = TranslationDirection(.english, to: .french)

    public var sourceCode: String { source.code }
    public var targetCode: String { target.code }

    /// "FR → EN", shown in the translation card.
    public var label: String { "\(source.shortName) → \(target.shortName)" }
    /// "fr-en", for logs.
    public var id: String { "\(source.code)-\(target.code)" }
}

/// A translation engine. Implementations keep line breaks and surrounding whitespace.
public protocol Translator: Sendable {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String
}
