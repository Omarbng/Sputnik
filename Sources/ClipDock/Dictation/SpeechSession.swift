import AVFoundation
import ClipDockCore
import Speech

/// One dictation's recognition, with Apple's on-device recognisers: `SpeechTranscriber` where
/// Apple's newer model has the language (English, French, German, Spanish …), otherwise
/// `DictationTranscriber` (Russian, Dutch, Turkish …). With several languages on, all listen and
/// `TranscriptPicker` keeps the one that understood.
@MainActor
final class SpeechSession {
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private var collectors: [(TranslationLanguage, Task<TranscriptCandidate, Never>)] = []

    private init(analyzer: SpeechAnalyzer, format: AVAudioFormat) {
        self.analyzer = analyzer
        self.format = format
    }

    /// The format the audio must be converted to.
    var audioFormat: AVAudioFormat { format }

    enum Problem: Error {
        case noLanguage
        case noFormat
    }

    /// Builds the recognisers and loads their models (fast after the first time: the models stay
    /// loaded while ClipDock runs).
    static func make(languages: [TranslationLanguage], vocabulary: [String]) async throws -> SpeechSession {
        var modules: [(TranslationLanguage, any SpeechModule)] = []
        for language in languages {
            guard let recogniser = await SpeechLanguages.recogniser(for: language) else { continue }
            modules.append((language, recogniser.module()))
        }
        guard !modules.isEmpty else { throw Problem.noLanguage }
        let speechModules = modules.map(\.1)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: speechModules) else { throw Problem.noFormat }
        let analyzer = SpeechAnalyzer(
            modules: speechModules,
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        )
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        let session = SpeechSession(analyzer: analyzer, format: format)
        for (language, module) in modules {
            session.collect(module, language: language)
        }
        try await analyzer.prepareToAnalyze(in: format)
        return session
    }

    /// Starts recognising the stream. Returns at once; results arrive as the audio does.
    func start(_ input: AsyncStream<AnalyzerInput>) async throws {
        try await analyzer.start(inputSequence: input)
    }

    /// After the stream has ended: waits for the last words and returns every reading.
    func finish() async -> [TranscriptCandidate] {
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            Log.dictation.error("finish failed: \(String(describing: type(of: error)), privacy: .public)")
            await analyzer.cancelAndFinishNow()
        }
        var candidates: [TranscriptCandidate] = []
        for (_, task) in collectors { candidates.append(await task.value) }
        return candidates
    }

    func cancel() async {
        await analyzer.cancelAndFinishNow()
        for (_, task) in collectors { task.cancel() }
    }

    // MARK: Results

    private func collect(_ module: any SpeechModule, language: TranslationLanguage) {
        let task: Task<TranscriptCandidate, Never>
        if let transcriber = module as? SpeechTranscriber {
            let results = transcriber.results.map { ($0.text, $0.isFinal) }
            task = Task { await self.read(results, language: language) }
        } else if let transcriber = module as? DictationTranscriber {
            let results = transcriber.results.map { ($0.text, $0.isFinal) }
            task = Task { await self.read(results, language: language) }
        } else {
            return
        }
        collectors.append((language, task))
    }

    private func read<S: AsyncSequence>(_ results: S, language: TranslationLanguage) async -> TranscriptCandidate
    where S.Element == (AttributedString, Bool) {
        var finished = AttributedString()
        do {
            for try await (text, isFinal) in results where isFinal {
                finished += text
            }
        } catch {
            Log.dictation.notice("results ended language=\(language.code, privacy: .public): \(String(describing: type(of: error)), privacy: .public)")
        }
        return TranscriptCandidate(
            language: language,
            text: String(finished.characters).trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: Self.confidence(of: finished)
        )
    }

    /// Average confidence over the text, weighted by length.
    static func confidence(of text: AttributedString) -> Double? {
        var total = 0.0
        var count = 0.0
        for run in text.runs {
            guard let confidence = run.transcriptionConfidence else { continue }
            let length = Double(text[run.range].characters.count)
            total += confidence * length
            count += length
        }
        return count > 0 ? total / count : nil
    }
}

/// Which recogniser serves each language, whether it's on this Mac, and Apple's download.
@MainActor
enum SpeechLanguages {
    struct Recogniser {
        enum Engine { case speech, dictation }
        let locale: Locale
        let engine: Engine

        func module() -> any SpeechModule {
            switch engine {
            case .speech:
                SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.transcriptionConfidence])
            case .dictation:
                DictationTranscriber(
                    locale: locale, contentHints: [], transcriptionOptions: [.punctuation],
                    reportingOptions: [.volatileResults], attributeOptions: [.transcriptionConfidence]
                )
            }
        }

        /// The smaller set of models to download.
        func downloadModule() -> any SpeechModule {
            switch engine {
            case .speech: SpeechTranscriber(locale: locale, preset: .transcription)
            case .dictation: DictationTranscriber(locale: locale, preset: .shortDictation)
            }
        }
    }

    /// The region each language is recognised in (Apple's recognisers need one).
    private static let locales: [String: String] = [
        "en": "en_US", "ru": "ru_RU", "fr": "fr_FR", "de": "de_DE", "es": "es_ES", "it": "it_IT",
        "pt": "pt_BR", "nl": "nl_NL", "tr": "tr_TR", "ar": "ar_SA", "ja": "ja_JP", "ko": "ko_KR",
        "zh": "zh_CN", "zh-TW": "zh_TW", "th": "th_TH", "vi": "vi_VN",
    ]
    private static var cache: [TranslationLanguage: Recogniser?] = [:]

    /// Apple's newer `SpeechTranscriber` when it has the language, else `DictationTranscriber`;
    /// nil when neither does (Hindi, Indonesian, Polish, Ukrainian). Checked against each
    /// engine's `supportedLocales`: `supportedLocale(equivalentTo:)` answers ru_RU for
    /// SpeechTranscriber, which has no Russian (2026-11-20, macOS 26.0).
    static func recogniser(for language: TranslationLanguage) async -> Recogniser? {
        if let cached = cache[language] { return cached }
        var found: Recogniser?
        if let identifier = locales[language.code] {
            let wanted = Locale(identifier: identifier)
            let bcp47 = wanted.identifier(.bcp47)
            if await SpeechTranscriber.supportedLocales.contains(where: { $0.identifier(.bcp47) == bcp47 }) {
                found = Recogniser(locale: wanted, engine: .speech)
            } else if await DictationTranscriber.supportedLocales.contains(where: { $0.identifier(.bcp47) == bcp47 }) {
                found = Recogniser(locale: wanted, engine: .dictation)
            }
        }
        cache[language] = found
        return found
    }

    static func canDictate(_ language: TranslationLanguage) async -> Bool {
        await recogniser(for: language) != nil
    }

    static func isInstalled(_ language: TranslationLanguage) async -> Bool {
        guard let recogniser = await recogniser(for: language) else { return false }
        let wanted = recogniser.locale.identifier(.bcp47)
        let installed = switch recogniser.engine {
        case .speech: await SpeechTranscriber.installedLocales
        case .dictation: await DictationTranscriber.installedLocales
        }
        return installed.contains { $0.identifier(.bcp47) == wanted }
    }

    /// The languages dictation listens for (from the setup), limited to what's installed.
    static func active() async -> [TranslationLanguage] {
        var result: [TranslationLanguage] = []
        for language in AppSettings.languages.spoken where await isInstalled(language) { result.append(language) }
        return result
    }

    /// Downloads Apple's recogniser for a language (a minute or two).
    static func download(_ language: TranslationLanguage) async throws {
        guard let recogniser = await recogniser(for: language) else { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [recogniser.downloadModule()]) {
            try await request.downloadAndInstall()
        }
        Log.dictation.notice("language installed=\(language.code, privacy: .public)")
    }
}
