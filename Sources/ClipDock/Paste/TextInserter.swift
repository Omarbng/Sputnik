import AppKit
import ClipDockCore

/// Types text into the frontmost app the way a paste does, then puts the clipboard back:
/// save the clipboard, write the text (marked internal), ⌘V, restore after 500 ms.
/// Where pasting can't work (secure input, no Accessibility, ClipDock in front), the text is
/// left copied and a HUD says so.
@MainActor
final class TextInserter {
    static let restoreDelay: Duration = .milliseconds(500)

    private let capture: CaptureController
    private let hud: HUDController

    init(capture: CaptureController, hud: HUDController) {
        self.capture = capture
        self.hud = hud
    }

    enum Outcome {
        case inserted
        case copiedInstead
    }

    /// Returns where the text went. `record` adds it to history (with its badge).
    @discardableResult
    func insert(_ text: String, record: CapturedClip?) async -> Outcome {
        let front = NSWorkspace.shared.frontmostApplication
        let isClipDock = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        guard AccessibilityAccess.isTrusted, !isClipDock, !SecureInput.isEnabled else {
            PasteboardWriter.write(text: text)
            if let record { capture.record(record) }
            hud.show(SecureInput.isEnabled ? "Can't type here — copied instead" : "Copied — press ⌘V", style: .error)
            return .copiedInstead
        }
        await KeySender.waitForModifierRelease()  // fn + ⇧ still held would make it ⇧⌘V
        capture.beginIgnoringChanges()
        let snapshot = PasteboardSnapshot.take()
        PasteboardWriter.write(text: text)
        KeySender.commandV()
        try? await Task.sleep(for: Self.restoreDelay)
        snapshot.restore()
        capture.endIgnoringChanges()
        if let record { capture.record(record) }
        return .inserted
    }

    /// Copies the frontmost app's selection with ⌘C and puts the clipboard back at once.
    /// Nil when nothing is selected.
    func selectedText() async -> String? {
        guard AccessibilityAccess.isTrusted, !SecureInput.isEnabled else { return nil }
        capture.beginIgnoringChanges()
        let snapshot = PasteboardSnapshot.take()
        let grabbed = await SelectionGrabber.copySelection(timeout: TranslationService.copyTimeout)
        if grabbed != .nothingCopied { snapshot.restore() }
        capture.endIgnoringChanges()
        if case .text(let text) = grabbed { return text }
        return nil
    }
}
