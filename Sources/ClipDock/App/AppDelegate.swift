import AppKit
import ClipDockCore
@preconcurrency import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = HistoryModel()
    private let hud = HUDController()
    private let icons = AppIconCache()
    private let pasteAccessCard = PasteAccessWindowController()
    private let accessibilityCard = AccessibilityCardController()
    private let languageCard = LanguagePackCardController()
    private var capture: CaptureController?
    private var translation: TranslationService?
    private var popup: PopupController?
    private var statusItem: StatusItemController?
    #if DEBUG
    private var debugHooks: DebugHooks?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let database = openDatabase() else { return }

        let history = self.history
        let hud = self.hud
        let pasteAccessCard = self.pasteAccessCard
        let accessibilityCard = self.accessibilityCard
        let languageCard = self.languageCard

        let pipeline = CapturePipeline(database: database) { change in history.apply(change) }
        let capture = CaptureController(pipeline: pipeline)
        let translation = TranslationService(
            translator: Self.makeTranslator(),
            hud: hud,
            capture: capture,
            card: TranslationCardController(),
            hooks: .init(
                needsLanguagePacks: { languageCard.show() },
                needsAccessibility: { accessibilityCard.show() }
            )
        )
        let actions = ItemActions(database: database, history: history, paster: Paster(hud: hud), hud: hud, translation: translation)
        let thumbnails = ThumbnailCache(blobs: database.blobs)
        let popup = PopupController(history: history, icons: icons, thumbnails: thumbnails, actions: actions, translation: translation)

        let statusItem = StatusItemController(actions: .init(
            isCapturing: { [weak capture] in capture?.isCapturing ?? false },
            canPaste: { AccessibilityAccess.isTrusted },
            needsLanguages: { languageCard.isMissing },
            openPopup: { [weak popup] in popup?.show() },
            allowCapture: { [weak capture] in
                pasteAccessCard.show(access: capture?.access ?? PasteboardAccess.behavior)
            },
            allowPasting: { accessibilityCard.show() },
            downloadLanguages: { languageCard.show() }
        ))
        capture.onAccessChange = { [weak statusItem] access in
            statusItem?.refreshIcon()
            pasteAccessCard.update(access: access)
        }
        languageCard.onReady = { hud.show("Translation is ready") }

        KeyboardShortcuts.onKeyDown(for: .openPopup) { [weak popup] in popup?.toggle() }
        // Translation shortcuts fire on key-up, so the T key is released before ClipDock sends ⌘C.
        KeyboardShortcuts.onKeyUp(for: .translateInPlace) { [weak translation] in translation?.translateSelectionInPlace() }
        KeyboardShortcuts.onKeyUp(for: .translateShowOnly) { [weak translation] in translation?.translateSelectionShowOnly() }

        capture.start()
        statusItem.refreshIcon()
        warmCaches(thumbnails: thumbnails)
        DispatchQueue.main.async { popup.prewarm() }

        self.capture = capture
        self.translation = translation
        self.popup = popup
        self.statusItem = statusItem
        #if DEBUG
        // Test-only remote control. Off unless launched with `open --env CLIPDOCK_DEBUG_HOOKS=1`,
        // because any local process could otherwise drive pastes through ClipDock's permissions.
        if ProcessInfo.processInfo.environment["CLIPDOCK_DEBUG_HOOKS"] == "1" {
            debugHooks = DebugHooks(popup: popup, translation: translation)
        }
        #endif
        Log.app.notice("launched accessibility=\(AccessibilityAccess.isTrusted, privacy: .public) secureInputCheck=\(SecureInput.isAvailable, privacy: .public)")

        let showedCard = showOnboardingIfNeeded(access: capture.access)
        Task {
            await languageCard.refreshStatus()
            Log.translate.notice("language files missing=\(languageCard.isMissing, privacy: .public)")
            if !showedCard, languageCard.isMissing, !AppSettings.didShowLanguageCard {
                AppSettings.didShowLanguageCard = true
                languageCard.show()
            }
        }
    }

    private static func makeTranslator() -> any Translator {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CLIPDOCK_FAKE_TRANSLATOR"] == "1" {
            Log.translate.notice("using the fake translator")
            return FakeTranslator()
        }
        #endif
        return AppleTranslator()
    }

    private func openDatabase() -> HistoryDatabase? {
        do {
            let database = try HistoryDatabase(directory: AppPaths.supportDirectory())
            let expired = try database.applyRetention(AppSettings.retention, now: .now)
            history.replaceAll(with: try database.allItems())
            Log.storage.notice("history loaded items=\(self.history.items.count, privacy: .public) expired=\(expired.count, privacy: .public)")
            return database
        } catch {
            Log.storage.error("cannot open history: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "ClipDock can't open its history"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return nil
        }
    }

    /// Looks up app icons and first thumbnails now, so the first popup open is as fast as later ones.
    private func warmCaches(thumbnails: ThumbnailCache) {
        let recent = history.items.prefix(50)
        icons.warm(recent.map(\.sourceBundleID))
        let imageBlobs = recent.compactMap(\.imageBlob).prefix(8)
        Task {
            for blob in imageBlobs { _ = await thumbnails.load(blob) }
        }
    }

    /// Each card appears on its own once. After that, the menu offers it while it's needed.
    /// Returns whether a card was shown, so the cards don't pile up.
    private func showOnboardingIfNeeded(access: NSPasteboard.AccessBehavior) -> Bool {
        if access != .alwaysAllow, !AppSettings.didShowPasteAccessCard {
            AppSettings.didShowPasteAccessCard = true
            pasteAccessCard.show(access: access)
            return true
        }
        if !AccessibilityAccess.isTrusted, !AppSettings.didShowAccessibilityCard {
            AppSettings.didShowAccessibilityCard = true
            accessibilityCard.show()
            return true
        }
        return false
    }
}
