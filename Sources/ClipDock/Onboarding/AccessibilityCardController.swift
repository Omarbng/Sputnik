import AppKit

/// Shows the Accessibility card and closes it as soon as the permission is granted.
@MainActor
final class AccessibilityCardController {
    private let card = CardWindow()
    private var timer: Timer?

    init() {
        card.onClose = { [weak self] in self?.stopWatching() }
    }

    func show() {
        guard !AccessibilityAccess.isTrusted else { return }
        card.show(AccessibilityCardView(
            onContinue: { [weak self] in self?.requestAccess() },
            onDismiss: { [card] in card.close() }
        ))
        startWatching()
    }

    /// macOS shows its own prompt only once per app. After that, go straight to Settings.
    private func requestAccess() {
        if AppSettings.didPromptAccessibility {
            AccessibilityAccess.openSettings()
        } else {
            AppSettings.didPromptAccessibility = true
            AccessibilityAccess.request()
        }
    }

    private func startWatching() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AccessibilityAccess.isTrusted else { return }
                Log.paste.notice("accessibility granted")
                self?.card.close()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}
