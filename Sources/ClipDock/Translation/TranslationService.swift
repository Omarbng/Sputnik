import AppKit
import ClipDockCore

/// Translation: the selected text in any app (double-tap ⌃ → card), and a popup row (⌘T).
@MainActor
final class TranslationService {
    /// How long to wait for the target app to answer ⌘C. Electron apps (Cursor, Slack) can be
    /// slower than native ones; the wait ends as soon as the copy arrives.
    static let copyTimeout: Duration = .milliseconds(600)
    /// How long the target app gets to read the translation before the clipboard is restored.
    static let restoreDelay: Duration = .milliseconds(500)
    /// Translations faster than this show no "Translating…" HUD.
    static let progressDelay: Duration = .milliseconds(150)

    struct Hooks {
        /// The language files for this direction (and any other missing ones) need downloading.
        var needsLanguagePacks: (TranslationDirection?) -> Void
        var needsAccessibility: () -> Void
    }

    /// Text in the main language with no other language set up to translate it into.
    struct NoTarget: Error {}

    private let translator: any Translator
    private let hud: HUDController
    private let capture: CaptureController
    private let card: TranslationCardController
    private let hooks: Hooks
    private var isBusy = false
    /// "Reply in their language": the last foreign language translated, for an hour.
    private var reply = ReplyLanguageMemory()

    init(translator: any Translator, hud: HUDController, capture: CaptureController, card: TranslationCardController, hooks: Hooks) {
        self.translator = translator
        self.hud = hud
        self.capture = capture
        self.card = card
        self.hooks = hooks
    }

    // MARK: Shortcut

    /// Double-tap ⌃ (or the optional key combo): translate the selected text and show it in a
    /// card at the cursor. In the card, ↩ replaces the selection (⌘Z in the app undoes it),
    /// ⌘C copies, and Esc closes.
    func translateSelection() {
        guard !isBusy, canReadSelection() else { return }
        isBusy = true
        Task {
            await showCard()
            isBusy = false
        }
    }

    // MARK: Popup and shared helpers

    /// For ⌘T in the popup. The row shows progress, so there's no HUD.
    func translate(_ text: String) async throws -> String {
        guard let direction = direction(for: text) else { throw NoTarget() }
        Log.translate.notice("row direction=\(direction.id, privacy: .public) chars=\(text.count, privacy: .public)")
        return try await translate(text, direction: direction)
    }

    /// Into a language someone named ("translate to German"). Text already in it comes back as
    /// is. Apple translates most pairs directly; the few it doesn't go through English.
    func translate(_ text: String, into target: TranslationLanguage) async throws -> String {
        let setup = AppSettings.languages
        let source = LanguageDetector.language(of: text, among: Array(Set(setup.all + [target])), main: setup.main)
        guard source != target else { return text }
        if source != .english, target != .english, !(await LanguagePacks.isSupported(TranslationDirection(source, to: target))) {
            let english = try await translate(text, direction: TranslationDirection(source, to: .english))
            return try await translate(english, direction: TranslationDirection(.english, to: target))
        }
        return try await translate(text, direction: TranslationDirection(source, to: target))
    }

    /// Other languages go into the main one. The main one goes into the conversation's language
    /// when "Reply in their language" remembers one, otherwise into the one picked in Settings.
    /// Nil when nothing else is set up.
    func direction(for text: String) -> TranslationDirection? {
        LanguageDetector.direction(for: text, setup: AppSettings.languages, target: currentTarget)
    }

    /// Where the main language goes right now.
    var currentTarget: TranslationLanguage? {
        let fallback = AppSettings.languages.target
        guard AppSettings.isOn(.replyInTheirLanguage) else { return fallback }
        return reply.target(default: fallback, now: .now)
    }

    /// Every translation goes through here, so the reply language follows the conversation.
    private func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        do {
            let result = try await translator.translate(text, direction: direction)
            reply.noteTranslation(from: direction.source, main: AppSettings.languages.main, at: .now)
            return result
        } catch {
            if LanguagePacks.isNotInstalled(error) { missingDirection = direction }
            throw error
        }
    }

    /// The last direction that failed for want of its language files, for the download card.
    private var missingDirection: TranslationDirection?

    /// Adds a translation to history with the "translated" badge.
    func record(_ translation: String, from app: NSRunningApplication?) {
        capture.record(CapturedClip(
            payload: .text(translation, rtf: nil),
            sourceBundleID: app?.bundleIdentifier,
            sourceAppName: app?.localizedName,
            capturedAt: .now,
            isTranslation: true
        ))
    }

    /// A short message for `error`. Also offers the language download when that's the cause.
    func describe(_ error: Error) -> String {
        Log.translate.error("failed: \(String(describing: error), privacy: .public)")
        if error is NoTarget {
            return "Add a language to translate into in Settings → Translation"
        }
        if LanguagePacks.isNotInstalled(error) {
            hooks.needsLanguagePacks(missingDirection)
            return "Download the language files first"
        }
        return "Translation failed"
    }

    // MARK: Private

    private func showCard() async {
        let target = NSWorkspace.shared.frontmostApplication
        capture.beginIgnoringChanges()
        let snapshot = PasteboardSnapshot.take()
        let grabbed = await SelectionGrabber.copySelection(timeout: Self.copyTimeout)
        if grabbed != .nothingCopied { snapshot.restore() }  // the temporary ⌘C copy is never kept
        capture.endIgnoringChanges()

        // Nothing selected (WhatsApp messages can't be selected): translate what was just copied.
        let fromClipboard = grabbed == .nothingCopied && AppSettings.isOn(.translateClipboard)
        let text: String
        if case .text(let selection) = grabbed {
            text = selection
        } else if fromClipboard, let copied = Self.copiedText() {
            text = copied
        } else {
            hud.show(fromClipboard ? "Select or copy some text first" : "Select some text first", style: .error)
            Log.translate.notice("stopped reason=\(grabbed == .nothingCopied ? "nothingCopied" : "notText", privacy: .public)")
            return
        }
        guard let direction = direction(for: text) else {
            hud.show(describe(NoTarget()), style: .error)
            return
        }
        let setup = AppSettings.languages
        let isReply = direction.source == setup.main && direction.target != setup.target
        do {
            let translation = try await translateShowingProgress(text, direction: direction)
            card.show(
                translation: translation,
                direction: direction,
                note: [fromClipboard ? "from clipboard" : nil, isReply ? "reply" : nil].compactMap { $0 }.joined(separator: " · "),
                primaryTitle: fromClipboard ? "Paste" : "Replace",
                onReplace: { [weak self] in self?.replaceSelection(with: translation, in: target) },
                onCopy: { [weak self] in
                    PasteboardWriter.write(text: translation)
                    self?.record(translation, from: target)
                    self?.hud.show("Copied")
                }
            )
            Log.translate.notice("""
                card direction=\(direction.id, privacy: .public) clipboard=\(fromClipboard, privacy: .public) \
                reply=\(isReply, privacy: .public) chars=\(text.count, privacy: .public)->\(translation.count, privacy: .public)
                """)
        } catch {
            hud.show(describe(error), style: .error)
        }
    }

    /// ↩ in the card: paste the translation over the still-selected text, then put the
    /// clipboard back the way it was.
    private func replaceSelection(with translation: String, in target: NSRunningApplication?) {
        Task {
            try? await Task.sleep(for: Paster.delay)  // let focus return to the app after the card closes
            guard let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  !SecureInput.isEnabled
            else {
                PasteboardWriter.write(text: translation)
                record(translation, from: target)
                hud.show("Copied — press ⌘V", style: .error)
                Log.translate.notice("replace fallback: target not frontmost or secure input")
                return
            }
            capture.beginIgnoringChanges()
            let snapshot = PasteboardSnapshot.take()
            PasteboardWriter.write(text: translation)
            KeySender.commandV()
            try? await Task.sleep(for: Self.restoreDelay)
            snapshot.restore()
            capture.endIgnoringChanges()
            record(translation, from: target)
            Log.translate.notice("replaced chars=\(translation.count, privacy: .public)")
        }
    }

    /// Shows "Translating…" only if the translation takes longer than `progressDelay`.
    private func translateShowingProgress(_ text: String, direction: TranslationDirection) async throws -> String {
        let hud = hud
        let progress = Task {
            try? await Task.sleep(for: Self.progressDelay)
            guard !Task.isCancelled else { return }
            hud.show("Translating…", autoHide: false)
        }
        defer {
            progress.cancel()
            hud.hide()
        }
        return try await translate(text, direction: direction)
    }

    /// The clipboard's text, unless it's a password or a secret (concealed) or too big.
    private static func copiedText() -> String? {
        let pasteboard = NSPasteboard.general
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: SkipRules.concealedTypes),
              let text = pasteboard.string(forType: .string),
              !text.allSatisfy(\.isWhitespace), text.utf8.count <= 200_000
        else { return nil }
        if case .url = ClipPayload.fromText(text, rtf: nil) { return nil }  // a link isn't for translating
        return text
    }

    /// ⌘C needs Accessibility, and secure input blocks it.
    private func canReadSelection() -> Bool {
        guard AccessibilityAccess.isTrusted else {
            Log.translate.notice("stopped reason=noAccessibility")
            hud.show("Sputnik needs Accessibility to read the selection", style: .error)
            hooks.needsAccessibility()
            return false
        }
        guard !SecureInput.isEnabled else {
            Log.translate.notice("stopped reason=secureInput")
            hud.show("Can't read the selection here", style: .error)
            return false
        }
        return true
    }
}
