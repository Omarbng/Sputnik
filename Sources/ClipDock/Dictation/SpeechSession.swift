import AVFoundation
import ClipDockCore
import Speech

/// One dictation's recognition, with Apple's on-device recognisers: `SpeechTranscriber` for
/// English and `DictationTranscriber` for Russian (Apple's new model has no Russian). With both
/// languages on, both listen and `TranscriptPicker` keeps the one that understood.
@MainActor
final class SpeechSession {
    /// The live text for the pill: finished phrases plus the one being heard.
    var onPreview: ((String) -> Void)?

    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private var collectors: [(TranslationLanguage, Task<TranscriptCandidate, Never>)] = []
    private var partials: [TranslationLanguage: String] = [:]

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
            switch language {
            case .english:
                modules.append((language, SpeechTranscriber(
                    locale: Locale(identifier: "en_US"), transcriptionOptions: [],
                    reportingOptions: [.volatileResults], attributeOptions: [.transcriptionConfidence]
                )))
            case .russian:
                modules.append((language, DictationTranscriber(
                    locale: Locale(identifier: "ru_RU"), contentHints: [],
                    transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults],
                    attributeOptions: [.transcriptionConfidence]
                )))
            case .french:
                continue  // Omar doesn't dictate in French (2026-11-19)
            }
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
            for try await (text, isFinal) in results {
                if isFinal {
                    finished += text
                    partials[language] = String(finished.characters)
                } else {
                    partials[language] = String(finished.characters) + String(text.characters)
                }
                publishPreview()
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

    /// The live text from whichever recogniser seems to be understanding.
    private func publishPreview() {
        let candidates = partials.map { TranscriptCandidate(language: $0.key, text: $0.value, confidence: nil) }
        guard let best = TranscriptPicker.pick(candidates) else { return }
        onPreview?(best.text)
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

/// Which dictation languages are on this Mac, and Apple's download for a missing one.
enum SpeechLanguages {
    static func isInstalled(_ language: TranslationLanguage) async -> Bool {
        switch language {
        case .english:
            await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47).hasPrefix("en-US") || $0.identifier == "en_US" }
        case .russian:
            await DictationTranscriber.installedLocales.contains { $0.identifier(.bcp47).hasPrefix("ru") }
        case .french:
            false
        }
    }

    /// The languages dictation listens for, from Settings, limited to what's installed.
    static func active() async -> [TranslationLanguage] {
        let wanted: [TranslationLanguage] = switch AppSettings.dictationLanguage {
        case .automatic: [.english, .russian]
        case .english: [.english]
        case .russian: [.russian]
        }
        var result: [TranslationLanguage] = []
        for language in wanted where await isInstalled(language) { result.append(language) }
        return result
    }

    /// Downloads Apple's recogniser for a language (Russian dictation is about a minute or two).
    static func download(_ language: TranslationLanguage) async throws {
        let module: any SpeechModule = switch language {
        case .russian: DictationTranscriber(locale: Locale(identifier: "ru_RU"), preset: .shortDictation)
        default: SpeechTranscriber(locale: Locale(identifier: "en_US"), preset: .transcription)
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        Log.dictation.notice("language installed=\(language.code, privacy: .public)")
    }
}
