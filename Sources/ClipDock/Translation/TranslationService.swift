import AppKit
import ClipDockCore

/// Translation: the selected text in any app (double-tap ⌃ → card), and a popup row (⌘T).
@MainActor
final class TranslationService {
    /// How long to wait for the target app to answer ⌘C.
    static let copyTimeout: Duration = .milliseconds(300)
    /// How long the target app gets to read the translation before the clipboard is restored.
    static let restoreDelay: Duration = .milliseconds(500)
    /// Translations faster than this show no "Translating…" HUD.
    static let progressDelay: Duration = .milliseconds(150)

    struct Hooks {
        var needsLanguagePacks: () -> Void
        var needsAccessibility: () -> Void
    }

    private let translator: any Translator
    private let hud: HUDController
    private let capture: CaptureController
    private let card: TranslationCardController
    private let hooks: Hooks
    private var isBusy = false

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
        try await translator.translate(text, direction: LanguageDetector.direction(for: text))
    }

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
        if LanguagePacks.isNotInstalled(error) {
            hooks.needsLanguagePacks()
            return "Download English and Russian first"
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

        guard case .text(let selection) = grabbed else {
            hud.show("Select some text first", style: .error)
            Log.translate.notice("stopped reason=\(grabbed == .nothingCopied ? "nothingCopied" : "notText", privacy: .public)")
            return
        }
        let direction = LanguageDetector.direction(for: selection)
        do {
            let translation = try await translateShowingProgress(selection, direction: direction)
            card.show(
                translation: translation,
                direction: direction,
                onReplace: { [weak self] in self?.replaceSelection(with: translation, in: target) },
                onCopy: { [weak self] in
                    PasteboardWriter.write(text: translation)
                    self?.record(translation, from: target)
                    self?.hud.show("Copied")
                }
            )
            Log.translate.notice("""
                card direction=\(direction.rawValue, privacy: .public) \
                chars=\(selection.count, privacy: .public)->\(translation.count, privacy: .public)
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
        return try await translator.translate(text, direction: direction)
    }

    /// ⌘C needs Accessibility, and secure input blocks it.
    private func canReadSelection() -> Bool {
        guard AccessibilityAccess.isTrusted else {
            Log.translate.notice("stopped reason=noAccessibility")
            hud.show("ClipDock needs Accessibility to read the selection", style: .error)
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
