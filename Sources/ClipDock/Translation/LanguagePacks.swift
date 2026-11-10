import ClipDockCore
@preconcurrency import Translation

enum LanguagePacks {
    /// Directions whose language files aren't downloaded yet.
    static func missingDirections() async -> [TranslationDirection] {
        let availability = LanguageAvailability()
        var missing: [TranslationDirection] = []
        for direction in TranslationDirection.allCases {
            let status = await availability.status(from: direction.sourceLanguage, to: direction.targetLanguage)
            if status != .installed { missing.append(direction) }
        }
        return missing
    }

    static func isNotInstalled(_ error: Error) -> Bool {
        TranslationError.notInstalled ~= error
    }
}
