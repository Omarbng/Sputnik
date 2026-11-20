import ClipDockCore
import Foundation
import Observation

/// Choosing languages, for both the first-launch setup and Settings: the main language, the
/// others, where the main one translates to, and which ones dictation listens for, with each
/// spoken language's recogniser status and download.
@MainActor
@Observable
final class LanguagesModel {
    enum SpeechState: Equatable {
        case checking
        /// Apple has no recogniser for it (Hindi, Indonesian, Polish, Ukrainian).
        case unavailable
        case notDownloaded
        case downloading
        case ready
        case failed
    }

    private(set) var setup = AppSettings.languages
    private(set) var speech: [TranslationLanguage: SpeechState] = [:]
    /// Apple's translation files still missing for the chosen languages.
    private(set) var translationFilesMissing = false

    /// Languages not chosen yet, for "Add Language".
    var addable: [TranslationLanguage] {
        TranslationLanguage.catalog.filter { !setup.all.contains($0) }
    }

    func reload() {
        setup = AppSettings.languages
        refresh()
    }

    func setMain(_ language: TranslationLanguage) {
        var setup = setup
        setup.setMain(language)
        if setup.spoken.isEmpty { setup.setSpoken([language]) }
        save(setup)
    }

    func add(_ language: TranslationLanguage) {
        var setup = setup
        setup.setOthers(setup.others + [language])
        save(setup)
    }

    func remove(_ language: TranslationLanguage) {
        var setup = setup
        setup.setOthers(setup.others.filter { $0 != language })
        save(setup)
    }

    func setTarget(_ language: TranslationLanguage?) {
        var setup = setup
        setup.setTarget(language)
        save(setup)
    }

    func isSpoken(_ language: TranslationLanguage) -> Bool {
        setup.spoken.contains(language)
    }

    /// Turns dictation in a language on or off (at most `LanguageSetup.maxSpoken`).
    func setSpoken(_ language: TranslationLanguage, _ on: Bool) {
        var setup = setup
        if on {
            guard setup.spoken.count < LanguageSetup.maxSpoken else { return }
            setup.setSpoken(setup.spoken + [language])
        } else {
            setup.setSpoken(setup.spoken.filter { $0 != language })
        }
        save(setup)
        if on, speech[language] == .notDownloaded { download(language) }
    }

    func canAddSpoken(_ language: TranslationLanguage) -> Bool {
        isSpoken(language) || setup.spoken.count < LanguageSetup.maxSpoken
    }

    func download(_ language: TranslationLanguage) {
        guard speech[language] != .downloading else { return }
        speech[language] = .downloading
        Task {
            do {
                try await SpeechLanguages.download(language)
                speech[language] = await SpeechLanguages.isInstalled(language) ? .ready : .failed
            } catch {
                Log.dictation.error("speech download failed language=\(language.code, privacy: .public)")
                speech[language] = .failed
            }
        }
    }

    private func save(_ setup: LanguageSetup) {
        self.setup = setup
        AppSettings.languages = setup
        Log.app.notice("""
            languages main=\(setup.main.code, privacy: .public) \
            others=\(setup.others.map(\.code).joined(separator: ","), privacy: .public) \
            target=\(setup.target?.code ?? "none", privacy: .public) \
            spoken=\(setup.spoken.map(\.code).joined(separator: ","), privacy: .public)
            """)
        refresh()
    }

    /// Re-checks recognisers and translation files for the chosen languages.
    func refresh() {
        let languages = setup.all
        Task {
            for language in languages where speech[language] != .downloading {
                if speech[language] == nil { speech[language] = .checking }
                speech[language] = if !(await SpeechLanguages.canDictate(language)) {
                    .unavailable
                } else if await SpeechLanguages.isInstalled(language) {
                    .ready
                } else {
                    speech[language] == .failed ? .failed : .notDownloaded
                }
            }
            translationFilesMissing = !(await LanguagePacks.missingDirections()).isEmpty
        }
    }
}
