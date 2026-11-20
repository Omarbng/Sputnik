import SputnikCore
@preconcurrency import Translation

/// Apple's translation language files: which ones the chosen languages still need.
enum LanguagePacks {
    /// Directions whose language files aren't downloaded yet: the setup's, plus `extra` (a
    /// language someone asked for by voice, say).
    static func missingDirections(extra: [TranslationDirection] = []) async -> [TranslationDirection] {
        let availability = LanguageAvailability()
        var missing: [TranslationDirection] = []
        for direction in AppSettings.languages.directions + extra where !missing.contains(direction) {
            let status = await availability.status(from: direction.sourceLanguage, to: direction.targetLanguage)
            if status == .supported { missing.append(direction) }  // .unsupported can't be downloaded
        }
        return missing
    }

    /// Whether Apple translates this pair at all (installed or downloadable).
    static func isSupported(_ direction: TranslationDirection) async -> Bool {
        await LanguageAvailability().status(from: direction.sourceLanguage, to: direction.targetLanguage) != .unsupported
    }

    static func isNotInstalled(_ error: Error) -> Bool {
        TranslationError.notInstalled ~= error
    }
}
