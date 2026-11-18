/// The languages ClipDock translates between. French and Russian always go into English;
/// English goes into Russian, or into French if Omar picks that in Settings.
public enum TranslationLanguage: String, Sendable, CaseIterable {
    case english = "en"
    case russian = "ru"
    case french = "fr"

    /// The BCP 47 code, as used by `Locale.Language(identifier:)`.
    public var code: String { rawValue }
    /// "EN", "RU", "FR", for the translation card.
    public var shortName: String { rawValue.uppercased() }

    public var name: String {
        switch self {
        case .english: "English"
        case .russian: "Russian"
        case .french: "French"
        }
    }

    /// What English text can be translated into. The first is the default.
    public static let englishTargets: [TranslationLanguage] = [.russian, .french]
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

    /// Every direction ClipDock can use. Their language files are downloaded up front, so
    /// switching English to French in Settings works at once.
    public static let all: [TranslationDirection] = [.englishToRussian, .russianToEnglish, .frenchToEnglish, .englishToFrench]

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
