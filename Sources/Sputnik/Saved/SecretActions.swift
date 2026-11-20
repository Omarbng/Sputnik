import AppKit
import SputnikCore

/// Pasting and copying secrets. Every use asks for Touch ID. The value goes on the clipboard
/// marked concealed (clipboard managers skip it), and only briefly: after a paste the previous
/// clipboard comes back at once; a copy is cleared after 30 seconds.
@MainActor
final class SecretActions {
    static let copyLifetime: Duration = .seconds(30)
    /// Time for the target app to read the pasteboard after ⌘V (as in translation).
    static let restoreDelay: Duration = .milliseconds(500)

    private let hud: HUDController
    private let capture: CaptureController
    /// What to put back when a copied secret is cleared, and the change count it was written at.
    private var pendingRestore: (snapshot: PasteboardSnapshot, changeCount: Int)?
    private var clearTask: Task<Void, Never>?

    init(hud: HUDController, capture: CaptureController) {
        self.hud = hud
        self.capture = capture
    }

    /// The popup has closed; `target` is the app that was frontmost behind it.
    func paste(_ item: ClipItem, into target: NSRunningApplication?, onUsed: @escaping () -> Void) {
        Task {
            guard let value = await unlock(item, verb: "paste") else { return }
            onUsed()
            await bringBack(target)
            guard let target, Self.isFrontmost(target), AccessibilityAccess.isTrusted, !SecureInput.isEnabled else {
                let secure = SecureInput.isEnabled
                keepCopied(value, message: secure ? "Can't paste here — copied for 30 s" : "Copied for 30 s — press ⌘V")
                Log.paste.notice("secret fallback id=\(item.id ?? -1, privacy: .public) secureInput=\(secure, privacy: .public)")
                return
            }
            capture.beginIgnoringChanges()
            let snapshot = snapshotBeforeWriting()
            PasteboardWriter.write(secret: value)
            let written = NSPasteboard.general.changeCount
            try? await Task.sleep(for: Paster.delay)
            KeySender.commandV()
            try? await Task.sleep(for: Self.restoreDelay)
            if NSPasteboard.general.changeCount == written { snapshot.restore() }
            capture.endIgnoringChanges()
            Log.paste.notice("paste secret id=\(item.id ?? -1, privacy: .public)")
        }
    }

    func copy(_ item: ClipItem, onUsed: @escaping () -> Void) {
        Task {
            guard let value = await unlock(item, verb: "copy") else { return }
            onUsed()
            keepCopied(value, message: "Copied — clears in 30 s")
            Log.paste.notice("copy secret id=\(item.id ?? -1, privacy: .public)")
        }
    }

    // MARK: Private

    private func unlock(_ item: ClipItem, verb: String) async -> String? {
        guard let account = item.secretRef else { return nil }
        guard await OwnerCheck.confirm("\(verb) “\(item.displayTitle)”") else { return nil }
        do {
            return try await Task.detached { try SecretStore.read(account: account) }.value
        } catch {
            hud.show("Couldn't read it from the Keychain", style: .error)
            Log.paste.error("secret read failed id=\(item.id ?? -1, privacy: .public) \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The Touch ID prompt can take focus. Give it back to the app the paste is for.
    private func bringBack(_ target: NSRunningApplication?) async {
        guard let target, !target.isTerminated, !Self.isFrontmost(target) else { return }
        target.activate(options: [])
        for _ in 0..<10 where !Self.isFrontmost(target) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func keepCopied(_ value: String, message: String) {
        capture.beginIgnoringChanges()
        let snapshot = snapshotBeforeWriting()
        PasteboardWriter.write(secret: value)
        let written = NSPasteboard.general.changeCount
        capture.endIgnoringChanges()
        pendingRestore = (snapshot, written)
        hud.show(message, style: .error)

        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.copyLifetime)
            guard !Task.isCancelled else { return }
            self?.clearCopiedSecret()
        }
    }

    /// Puts the old clipboard back, unless something else was copied since.
    private func clearCopiedSecret() {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        guard NSPasteboard.general.changeCount == pending.changeCount else { return }
        capture.beginIgnoringChanges()
        pending.snapshot.restore()
        capture.endIgnoringChanges()
        Log.paste.notice("secret cleared from the clipboard")
    }

    /// The clipboard as it was before any secret: if a copied secret is still on it, what was
    /// there before that one.
    private func snapshotBeforeWriting() -> PasteboardSnapshot {
        if let pending = pendingRestore, NSPasteboard.general.changeCount == pending.changeCount {
            pendingRestore = nil
            clearTask?.cancel()
            return pending.snapshot
        }
        return PasteboardSnapshot.take()
    }

    private static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }
}
