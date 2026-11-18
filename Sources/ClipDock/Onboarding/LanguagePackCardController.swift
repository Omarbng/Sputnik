import AppKit

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

    func refreshStatus() async {
        isMissing = !(await LanguagePacks.missingDirections()).isEmpty
    }

    func show() {
        guard !card.isShowing else { return }
        card.show(LanguagePackCardView(onDismiss: { [card] in card.close() }))
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
