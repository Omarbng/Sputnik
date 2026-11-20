import AppKit

/// Copies the frontmost app's selection by sending ⌘C.
@MainActor
enum SelectionGrabber {
    enum Result: Equatable {
        /// The pasteboard didn't change in time: nothing was selected (or the app ignored ⌘C).
        case nothingCopied
        /// Something was copied, but it isn't text (an image, a file …).
        case notText
        case text(String)
    }

    static func copySelection(timeout: Duration) async -> Result {
        await KeySender.waitForModifierRelease()
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        KeySender.commandC()

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            guard pasteboard.changeCount != before else { continue }
            // Some apps clear the pasteboard first and write a moment later.
            for _ in 0..<5 {
                if let text = pasteboard.string(forType: .string),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .text(text)
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return .notText
        }
        // The app (bundle id only) helps tell "nothing selected" from "this app ignores ⌘C".
        Log.paste.notice("copy: nothing copied app=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public)")
        return .nothingCopied
    }
}
