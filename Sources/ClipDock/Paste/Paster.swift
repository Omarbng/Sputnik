import AppKit

/// The last steps of pasting, once the item is on the pasteboard and the popup has closed:
/// wait briefly, then send ⌘V to the frontmost app. When pasting isn't possible, the item
/// stays copied and a HUD says so.
@MainActor
final class Paster {
    /// Time for keyboard focus to return to the target app before ⌘V. Electron apps and
    /// terminals sometimes need longer (gotcha 8.4); tune it here.
    static let delay: Duration = .milliseconds(50)

    private let hud: HUDController

    init(hud: HUDController) {
        self.hud = hud
    }

    func pasteIntoFrontApp() {
        // Right after one of ClipDock's own windows, ClipDock can still be the active app.
        // ⌘V would then land in ClipDock, so leave the item copied instead.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            hud.show("Copied — press ⌘V", style: .error)
            Log.paste.notice("fallback reason=clipDockFrontmost")
            return
        }
        guard AccessibilityAccess.isTrusted else {
            hud.show("Copied — press ⌘V", style: .error)
            Log.paste.notice("fallback reason=noAccessibility")
            return
        }
        Task {
            try? await Task.sleep(for: Self.delay)
            if SecureInput.isEnabled {
                hud.show("Can't paste here — copied instead", style: .error)
                Log.paste.notice("fallback reason=secureInput")
                return
            }
            KeySender.commandV()
        }
    }
}
