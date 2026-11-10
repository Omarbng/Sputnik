import AppKit
import ClipDockCore

/// Translation actions: in place (⌥⌘T), show only (⇧⌥⌘T), and for a popup row (⌘T).
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

    // MARK: Shortcuts

    /// ⌥⌘T. Replaces the selection with its translation; ⌘Z in the app undoes it.
    func translateSelectionInPlace() {
        guard !isBusy, canReadSelection() else { return }
        isBusy = true
        Task {
            await inPlace()
            isBusy = false
        }
    }

    /// ⇧⌥⌘T. Shows the translation in a card at the cursor and doesn't change anything.
    func translateSelectionShowOnly() {
        guard !isBusy, canReadSelection() else { return }
        isBusy = true
        Task {
            await showOnly()
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

    private func inPlace() async {
        let target = NSWorkspace.shared.frontmostApplication
        capture.beginIgnoringChanges()
        let snapshot = PasteboardSnapshot.take()

        let selection: String
        switch await SelectionGrabber.copySelection(timeout: Self.copyTimeout) {
        case .nothingCopied:
            capture.endIgnoringChanges()
            hud.show("Select some text first", style: .error)
            Log.translate.notice("inPlace stopped reason=nothingCopied")
            return
        case .notText:
            snapshot.restore()
            capture.endIgnoringChanges()
            hud.show("Select some text first", style: .error)
            Log.translate.notice("inPlace stopped reason=notText")
            return
        case .text(let text):
            selection = text
        }

        let direction = LanguageDetector.direction(for: selection)
        let translation: String
        do {
            translation = try await translateShowingProgress(selection, direction: direction)
        } catch {
            snapshot.restore()
            capture.endIgnoringChanges()
            hud.show(describe(error), style: .error)
            return
        }

        PasteboardWriter.write(text: translation)
        KeySender.commandV()
        try? await Task.sleep(for: Self.restoreDelay)
        snapshot.restore()
        capture.endIgnoringChanges()
        record(translation, from: target)
        Log.translate.notice("""
            inPlace direction=\(direction.rawValue, privacy: .public) \
            chars=\(selection.count, privacy: .public)->\(translation.count, privacy: .public)
            """)
    }

    private func showOnly() async {
        let source = NSWorkspace.shared.frontmostApplication
        capture.beginIgnoringChanges()
        let snapshot = PasteboardSnapshot.take()
        let grabbed = await SelectionGrabber.copySelection(timeout: Self.copyTimeout)
        if grabbed != .nothingCopied { snapshot.restore() }
        capture.endIgnoringChanges()

        guard case .text(let selection) = grabbed else {
            hud.show("Select some text first", style: .error)
            Log.translate.notice("showOnly stopped reason=\(grabbed == .nothingCopied ? "nothingCopied" : "notText", privacy: .public)")
            return
        }
        let direction = LanguageDetector.direction(for: selection)
        do {
            let translation = try await translateShowingProgress(selection, direction: direction)
            card.show(translation: translation, direction: direction) { [weak self] in
                PasteboardWriter.write(text: translation)
                self?.record(translation, from: source)
                self?.hud.show("Copied")
            }
            Log.translate.notice("""
                showOnly direction=\(direction.rawValue, privacy: .public) \
                chars=\(selection.count, privacy: .public)->\(translation.count, privacy: .public)
                """)
        } catch {
            hud.show(describe(error), style: .error)
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
