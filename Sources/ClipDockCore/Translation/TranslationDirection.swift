/// ClipDock translates between English and Russian only.
public enum TranslationDirection: String, Sendable, CaseIterable {
    case englishToRussian
    case russianToEnglish

    /// BCP 47 codes, as used by `Locale.Language(identifier:)`.
    public var sourceCode: String { self == .englishToRussian ? "en" : "ru" }
    public var targetCode: String { self == .englishToRussian ? "ru" : "en" }

    public var label: String { self == .englishToRussian ? "EN → RU" : "RU → EN" }
}

/// A translation engine. Implementations keep line breaks and surrounding whitespace.
public protocol Translator: Sendable {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String
}
