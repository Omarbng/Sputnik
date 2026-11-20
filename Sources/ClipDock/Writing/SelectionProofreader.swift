import AppKit
import ClipDockCore

/// Double-tap ⇧ (changeable in Settings): proofread the selected text, in any app, in place.
/// Apple Intelligence fixes spelling, grammar and punctuation on this Mac; ⌘Z in the app undoes
/// it. With nothing to fix, or a result that isn't a plausible correction, the text is left
/// alone and a HUD says so. The corrected text also goes into history.
@MainActor
final class SelectionProofreader {
    private let writing: WritingAssistant
    private let inserter: TextInserter
    private let hud: HUDController
    private let needsAccessibility: () -> Void
    private var isBusy = false

    init(writing: WritingAssistant, inserter: TextInserter, hud: HUDController, needsAccessibility: @escaping () -> Void) {
        self.writing = writing
        self.inserter = inserter
        self.hud = hud
        self.needsAccessibility = needsAccessibility
    }

    func proofreadSelection() {
        guard !isBusy else { return }
        guard AccessibilityAccess.isTrusted else {
            hud.show("ClipDock needs Accessibility to read the selection", style: .error)
            needsAccessibility()
            return
        }
        guard !SecureInput.isEnabled else {
            hud.show("Can't read the selection here", style: .error)
            return
        }
        guard writing.isAvailable else {
            hud.show(writing.unavailableReason ?? "Apple Intelligence isn't available", style: .error)
            return
        }
        isBusy = true
        writing.prewarm()  // loads the model while ⌘C runs
        Task {
            await run()
            isBusy = false
        }
    }

    private func run() async {
        let target = NSWorkspace.shared.frontmostApplication
        guard let selection = await inserter.selectedText(), !selection.allSatisfy(\.isWhitespace) else {
            hud.show("Select some text first", style: .error)
            Log.writing.notice("proofread stopped reason=nothingSelected")
            return
        }
        let corrected: String
        do {
            corrected = try await rewriteShowingProgress(selection)
        } catch let failure as WritingAssistant.Unavailable {
            hud.show(failure.message, style: .error)
            return
        } catch {
            hud.show("Apple Intelligence couldn't do it", style: .error)
            return
        }
        switch ProofreadOutcome.of(original: selection, corrected: corrected) {
        case .unchanged:
            hud.show("No mistakes found")
            Log.writing.notice("proofread outcome=unchanged chars=\(selection.count, privacy: .public)")
        case .implausible:
            hud.show("Couldn't proofread this — left it as it was", style: .error)
            Log.writing.notice("proofread outcome=implausible chars=\(selection.count, privacy: .public)->\(corrected.count, privacy: .public)")
        case .corrected(let text):
            // The paste must go where the text was selected.
            guard let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                PasteboardWriter.write(text: text)
                hud.show("Copied — press ⌘V", style: .error)
                Log.writing.notice("proofread outcome=copied reason=appChanged")
                return
            }
            let outcome = await inserter.insert(text, record: CapturedClip(
                payload: .fromText(text, rtf: nil),
                sourceBundleID: target.bundleIdentifier,
                sourceAppName: target.localizedName,
                capturedAt: .now
            ))
            if outcome == .inserted { hud.show("Proofread — ⌘Z undoes it") }
            Log.writing.notice("proofread outcome=corrected chars=\(selection.count, privacy: .public)->\(text.count, privacy: .public)")
        }
    }

    /// Shows "Proofreading…" only if it takes longer than a moment.
    private func rewriteShowingProgress(_ text: String) async throws -> String {
        let hud = hud
        let progress = Task {
            try? await Task.sleep(for: TranslationService.progressDelay)
            guard !Task.isCancelled else { return }
            hud.show("Proofreading…", autoHide: false)
        }
        defer {
            progress.cancel()
            hud.hide()
        }
        return try await writing.rewrite(text, style: .proofread)
    }
}
