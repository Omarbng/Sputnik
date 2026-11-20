import Foundation

/// "Reply in their language": after a message in another language is translated into the main
/// one (Omar: French or Russian into English), text in the main language goes back into that
/// language for a while, without touching Settings.
public struct ReplyLanguageMemory: Sendable, Equatable {
    /// How long the conversation's language is remembered after the last foreign translation.
    public static let window: TimeInterval = 60 * 60

    public private(set) var language: TranslationLanguage?
    public private(set) var since: Date?

    public init() {}

    /// Call after every translation. Only sources other than the main language are remembered.
    public mutating func noteTranslation(from source: TranslationLanguage, main: TranslationLanguage = .english, at time: Date) {
        guard source != main else { return }
        language = source
        since = time
    }

    /// The language the main one goes into now: the remembered one while it's fresh, otherwise
    /// the default from Settings.
    public func englishTarget(default fallback: TranslationLanguage, now: Date) -> TranslationLanguage {
        target(default: fallback, now: now) ?? fallback
    }

    public func target(default fallback: TranslationLanguage?, now: Date) -> TranslationLanguage? {
        guard let language, let since, now.timeIntervalSince(since) <= Self.window else { return fallback }
        return language
    }

    /// True while a remembered language overrides the default.
    public func isActive(now: Date, default fallback: TranslationLanguage?) -> Bool {
        target(default: fallback, now: now) != fallback
    }

    public mutating func forget() {
        language = nil
        since = nil
    }
}
