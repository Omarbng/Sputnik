import AppKit
import SputnikCore

/// Shows the language download card and closes it once every direction is installed.
@MainActor
final class LanguagePackCardController {
    private let card = CardWindow()
    private var timer: Timer?

    /// Last known state, for the menu. Refreshed at launch and while the card is open.
    private(set) var isMissing = false
    var onReady: (() -> Void)?

    init() {
        card.onClose = { [weak self] in self?.stopWatching() }
    }

    /// Directions asked for outside the setup (a voice command into another language).
    private var extra: [TranslationDirection] = []

    func refreshStatus() async {
        isMissing = !(await LanguagePacks.missingDirections(extra: extra)).isEmpty
    }

    /// `direction` adds a pair the setup doesn't cover.
    func show(adding direction: TranslationDirection? = nil) {
        if let direction, !extra.contains(direction) { extra.append(direction) }
        guard !card.isShowing else { return }
        let extra = extra
        card.show(LanguagePackCardView(extra: extra, onDismiss: { [card] in card.close() }))
        startWatching()
    }

    private func startWatching() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        Task { await checkInstalled() }
    }

    private func checkInstalled() async {
        await refreshStatus()
        guard !isMissing, card.isShowing else { return }
        Log.translate.notice("language files installed")
        card.close()
        onReady?()
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}
