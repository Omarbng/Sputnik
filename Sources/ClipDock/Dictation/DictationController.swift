import AVFoundation
import AppKit
import ClipDockCore

/// ClipDock's own Wispr Flow, on this Mac only.
/// - Hold fn, speak, let go: the text is typed where you are (and kept in history, "dictated").
/// - Double-tap fn: hands-free until fn again; Esc cancels.
/// - fn + ⌃: a command for the selected text ("translate to Russian", "make it shorter"), or
///   "insert <saved item>".
/// - fn + ⇧: typed translated (Russian → English; English → the reply language or Settings'),
///   or into the language said first ("in French, …").
/// - Right ⌥ works like fn when that switch is on (see `FnKeyMonitor`).
/// Audio stays in memory and is dropped after recognition. Logs hold durations, word counts,
/// languages and modes, never what was said.
@MainActor
final class DictationController {
    struct Dependencies {
        let capture: CaptureController
        let hud: HUDController
        let translation: TranslationService
        let writing: WritingAssistant
        let inserter: TextInserter
        let history: HistoryModel
        let actions: ItemActions
    }

    /// Hands-free stops by itself after this long.
    static let handsFreeLimit: Duration = .seconds(10 * 60)
    /// Shorter recordings are almost always an accidental hold.
    static let minimumDuration: TimeInterval = 0.4

    let monitor = FnKeyMonitor()
    let pill = DictationPill()
    private let deps: Dependencies
    private var audio: AudioCapture?
    private var sessionTask: Task<SpeechSession?, Never>?
    private var startedAt = Date.now
    /// Bumped on every start and cancel, so late async work from an old dictation is dropped.
    private var generation = 0
    private var isFinishing = false
    private var didExplainWispr = false

    init(_ deps: Dependencies) {
        self.deps = deps
        monitor.onOutput = { [weak self] output in self?.handle(output) }
    }

    /// True while listening or finishing, so the double-tap shortcuts stay quiet (⇧ and ⌃ are
    /// tapped during dictation to pick a mode).
    var isBusy: Bool { monitor.isListening || audio != nil || isFinishing }

    /// (Re)installs the fn monitor. Call again after Accessibility is granted.
    func start() {
        monitor.start()
    }

    /// Loads the speech models a few seconds after launch, so the first dictation is as quick
    /// as later ones. Skipped while dictation is off or the microphone isn't allowed.
    func prewarm() {
        guard AppSettings.isOn(.dictation), AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            let languages = await SpeechLanguages.active()
            guard !languages.isEmpty, let session = try? await SpeechSession.make(languages: languages, vocabulary: []) else { return }
            await session.cancel()
            Log.dictation.notice("prewarmed languages=\(languages.map(\.code).joined(separator: ","), privacy: .public)")
        }
    }

    private func handle(_ output: HoldToTalkDetector.Output) {
        switch output {
        case .begin:
            begin()
        case .confirm(let handsFree):
            guard audio != nil else { return }
            pill.state.phase = .listening
            pill.show()
            if handsFree { limitHandsFree() }
        case .modeChanged(let mode):
            pill.state.mode = mode
        case .cancel:
            cancel()
        case .finish(let mode):
            finish(mode)
        }
    }

    // MARK: Listening

    /// Wispr Flow listens to fn too; with both running, every dictation would be typed twice.
    static var wisprFlowIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier?.hasPrefix("com.electron.wispr-flow") == true }
    }

    private func begin() {
        guard AppSettings.isOn(.dictation), !isFinishing, audio == nil else { return }
        guard !Self.wisprFlowIsRunning else {
            if !didExplainWispr {
                didExplainWispr = true
                deps.hud.show("Wispr Flow has fn — quit it to dictate with Sputnik", style: .error)
            }
            Log.dictation.notice("stopped reason=wisprFlowRunning")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            deps.hud.show("Allow the microphone, then hold fn again", style: .error)
            return
        default:
            deps.hud.show("Allow the microphone in System Settings → Privacy", style: .error)
            Log.dictation.notice("stopped reason=noMicrophoneAccess")
            return
        }
        generation += 1
        let current = generation
        let audio = AudioCapture()
        let state = pill.state
        audio.onLevel = { level in Task { @MainActor in state.level = level } }
        do {
            try audio.start()
        } catch {
            deps.hud.show("Couldn't start the microphone", style: .error)
            Log.dictation.error("microphone failed: \(String(describing: Swift.type(of: error)), privacy: .public)")
            return
        }
        self.audio = audio
        startedAt = .now
        state.mode = .dictate
        state.phase = .listening
        if AppSettings.isOn(.dictationPolish) || AppSettings.isOn(.voiceCommands) { deps.writing.prewarm() }
        sessionTask = Task { [weak self] in
            await self?.openSession(for: audio, generation: current)
        }
    }

    #if DEBUG
    /// Tests: a dictation from an audio file instead of the microphone, through the same steps.
    func dictate(file url: URL, mode: DictationMode) {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil
        else { return }
        generation += 1
        let current = generation
        let audio = AudioCapture()
        audio.startWithoutMicrophone(source: file.processingFormat)
        audio.inject(buffer)
        self.audio = audio
        startedAt = Date.now.addingTimeInterval(-Double(file.length) / file.processingFormat.sampleRate)
        sessionTask = Task { [weak self] in
            await self?.openSession(for: audio, generation: current)
        }
        pill.state.mode = mode
        pill.state.phase = .listening
        pill.show()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            finish(mode)
        }
    }
    #endif

    private func openSession(for audio: AudioCapture, generation current: Int) async -> SpeechSession? {
        let languages = await SpeechLanguages.active()
        guard !languages.isEmpty else {
            Log.dictation.notice("stopped reason=noLanguageInstalled")
            return nil
        }
        do {
            // Saved items' names too, so "insert <name>" is heard right.
            let names = deps.history.items.filter(\.isPinned).compactMap(\.name)
            let session = try await SpeechSession.make(languages: languages, vocabulary: AppSettings.dictationVocabulary + names)
            guard current == generation, let stream = audio.stream else {
                await session.cancel()
                return nil
            }
            audio.setFormat(session.audioFormat)
            try await session.start(stream)
            return session
        } catch {
            Log.dictation.error("recogniser failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func cancel() {
        generation += 1
        audio?.discard()
        audio = nil
        let task = sessionTask
        sessionTask = nil
        Task { await task?.value?.cancel() }
        if !isFinishing { pill.hide() }
    }

    private func limitHandsFree() {
        let current = generation
        Task {
            try? await Task.sleep(for: Self.handsFreeLimit)
            guard current == generation, audio != nil else { return }
            let now = ProcessInfo.processInfo.systemUptime
            monitor.simulate([.fnDown(at: now), .fnUp(at: now + 0.05)])
        }
    }

    // MARK: Finishing

    private func finish(_ mode: DictationMode) {
        guard let audio, let sessionTask else { return }
        audio.stop()
        self.audio = nil
        self.sessionTask = nil
        let current = generation
        let duration = Date.now.timeIntervalSince(startedAt)
        guard duration >= Self.minimumDuration else {
            audio.discard()
            Task { await sessionTask.value?.cancel() }
            pill.hide()
            return
        }
        isFinishing = true
        pill.state.phase = .working
        Task {
            defer {
                isFinishing = false
                pill.hide()
            }
            guard let session = await sessionTask.value else {
                deps.hud.show("Dictation isn't ready — check Settings → Dictation", style: .error)
                return
            }
            let started = ContinuousClock.now
            let candidates = await session.finish()
            guard current == generation else { return }
            guard let best = TranscriptPicker.pick(candidates) else {
                deps.hud.show("Didn't catch that", style: .error)
                Log.dictation.notice("empty seconds=\(Int(duration), privacy: .public)")
                return
            }
            let text = AppSettings.isOn(.dictationRules) ? DictationCleanup.clean(best.text) : best.text
            Log.dictation.notice("""
                heard mode=\(mode.rawValue, privacy: .public) language=\(best.language.code, privacy: .public) \
                seconds=\(String(format: "%.1f", duration), privacy: .public) words=\(Self.words(text), privacy: .public) \
                finishMs=\(WritingAssistant.milliseconds(since: started), privacy: .public)
                """)
            switch mode {
            case .dictate: await deliver(text, language: best.language)
            case .translate: await deliverTranslated(text)
            case .command: await runCommand(text)
            }
        }
    }

    /// Plain dictation: "insert <saved item>", or the text (polished for English when that's on).
    private func deliver(_ spoken: String, language: TranslationLanguage) async {
        if AppSettings.isOn(.voiceCommands), let name = VoiceCommand.snippetName(in: spoken), await insertSaved(named: name) {
            return
        }
        var text = spoken
        if AppSettings.isOn(.dictationPolish), deps.writing.isAvailable {
            pill.state.phase = .working
            if let polished = try? await deps.writing.polishDictation(spoken, language: language),
               RewriteStyle.isPlausibleCleanup(original: spoken, cleaned: polished) {
                text = polished
            } else {
                Log.dictation.notice("polish skipped")
            }
        }
        await type(text, isTranslation: false)
    }

    /// fn + ⇧: Russian is typed in English; English in the reply language (or Settings').
    /// "In French, …" / "по-английски …" first picks the language for this one.
    private func deliverTranslated(_ spoken: String) async {
        pill.state.phase = .working
        var text = spoken
        var said: TranslationLanguage?
        if AppSettings.isOn(.sayLanguage), let split = SpokenLanguage.split(spoken) {
            guard !split.rest.isEmpty else {
                deps.hud.show("Say what to translate after the language", style: .error)
                return
            }
            text = split.rest
            said = split.language
        }
        do {
            let translated = if let said {
                try await deps.translation.translate(text, into: said)
            } else {
                try await deps.translation.translate(text)
            }
            Log.dictation.notice("translated saidLanguage=\(said?.code ?? "none", privacy: .public)")
            await type(translated, isTranslation: true)
        } catch {
            deps.hud.show(deps.translation.describe(error), style: .error)
        }
    }

    /// fn + ⌃: an instruction for the selected text, or "insert <saved item>".
    private func runCommand(_ instruction: String) async {
        guard AppSettings.isOn(.voiceCommands) else {
            deps.hud.show("Voice commands are off in Settings", style: .error)
            return
        }
        let command = VoiceCommand.parse(instruction)
        if case .insertSaved(let name) = command {
            if !(await insertSaved(named: name)) { deps.hud.show("No saved item called that", style: .error) }
            return
        }
        pill.state.phase = .working
        guard let selection = await deps.inserter.selectedText() else {
            deps.hud.show("Select some text, then hold fn + ⌃ and say what to do", style: .error)
            return
        }
        pill.state.phase = .working
        do {
            let result: String
            switch command {
            case .translate(let language):
                result = try await deps.translation.translate(selection, into: language)
            case .rewrite(let style):
                result = try await deps.writing.rewrite(selection, style: style)
            case .freeform(let text):
                result = try await deps.writing.apply(instruction: text, to: selection)
            case .insertSaved:
                return
            }
            Log.dictation.notice("command kind=\(Self.kind(of: command), privacy: .public) chars=\(selection.count, privacy: .public)->\(result.count, privacy: .public)")
            await deps.inserter.insert(result, record: clip(result, isDictation: false, isTranslation: { if case .translate = command { true } else { false } }()))
        } catch let failure as WritingAssistant.Unavailable {
            deps.hud.show(failure.message, style: .error)
        } catch {
            deps.hud.show(deps.translation.describe(error), style: .error)
        }
    }

    /// Pastes the saved item Omar named. Text goes in and the clipboard comes back; secrets
    /// and images paste the usual way (secrets after Touch ID).
    private func insertSaved(named name: String) async -> Bool {
        let saved = deps.history.items.filter { $0.isPinned && $0.name != nil }
        guard let index = SavedNameMatcher.match(spoken: name, names: saved.compactMap(\.name)) else { return false }
        let item = saved[index]
        Log.dictation.notice("snippet id=\(item.id ?? -1, privacy: .public)")
        if item.kind == .text, let text = item.text {
            await deps.inserter.insert(text, record: nil)
            deps.actions.markUsed(item)
        } else {
            deps.actions.paste(item, closePopup: {})
        }
        return true
    }

    private func type(_ text: String, isTranslation: Bool) async {
        await deps.inserter.insert(text, record: clip(text, isDictation: true, isTranslation: isTranslation))
    }

    private func clip(_ text: String, isDictation: Bool, isTranslation: Bool) -> CapturedClip {
        let front = NSWorkspace.shared.frontmostApplication
        return CapturedClip(
            payload: .fromText(text, rtf: nil),
            sourceBundleID: front?.bundleIdentifier,
            sourceAppName: front?.localizedName,
            capturedAt: .now,
            isTranslation: isTranslation,
            isDictation: isDictation
        )
    }

    private static func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func kind(of command: VoiceCommand) -> String {
        switch command {
        case .insertSaved: "snippet"
        case .translate(let language): "translate-\(language.code)"
        case .rewrite(let style): style.rawValue
        case .freeform: "freeform"
        }
    }
}
