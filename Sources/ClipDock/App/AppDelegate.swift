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
    private let doubleTaps = DoubleTapMonitor()
    private var capture: CaptureController?
    private var translation: TranslationService?
    private var popup: PopupController?
    private var settings: SettingsWindowController?
    private var maintenance: HistoryMaintenance?
    private var statusItem: StatusItemController?
    #if DEBUG
    private var debugHooks: DebugHooks?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.removeOldComboShortcutsOnce()  // before KeyboardShortcuts reads them
        guard let database = openDatabase() else { return }

        let history = self.history
        let hud = self.hud
        let pasteAccessCard = self.pasteAccessCard
        let accessibilityCard = self.accessibilityCard
        let languageCard = self.languageCard

        let pipeline = CapturePipeline(database: database) { change in history.apply(change) }
        let capture = CaptureController(pipeline: pipeline)
        let translationCard = TranslationCardController()
        let translation = TranslationService(
            translator: Self.makeTranslator(),
            hud: hud,
            capture: capture,
            card: translationCard,
            hooks: .init(
                needsLanguagePacks: { languageCard.show() },
                needsAccessibility: { accessibilityCard.show() }
            )
        )
        let actions = ItemActions(
            database: database, history: history, paster: Paster(hud: hud), hud: hud,
            translation: translation, capture: capture, secrets: SecretActions(hud: hud, capture: capture)
        )
        let saved = SavedItems(database: database, history: history)
        let thumbnails = ThumbnailCache(blobs: database.blobs)
        let popup = PopupController(
            history: history, icons: icons, thumbnails: thumbnails,
            actions: actions, saved: saved, translation: translation
        )
        let maintenance = HistoryMaintenance(database: database, history: history, hud: hud)
        let settings = SettingsWindowController(
            icons: icons,
            actions: .init(
                openAccessibilitySettings: { accessibilityCard.show() },
                openPasteSettings: { PasteboardAccess.openSettings() },
                downloadLanguages: { languageCard.show() }
            ),
            languagesMissing: { languageCard.isMissing }
        )
        settings.onClose = { limitsChanged in
            if limitsChanged { maintenance.applyRetention() }
        }
        popup.onOpenSettings = { settings.show() }

        let statusItem = StatusItemController(actions: .init(
            hasClipboardAccess: { [weak capture] in capture?.hasAccess ?? false },
            pausedUntil: { [weak capture] in capture?.pausedUntil },
            canPaste: { AccessibilityAccess.isTrusted },
            needsLanguages: { languageCard.isMissing },
            openPopup: { [weak popup] in popup?.show() },
            pause: { [weak capture] seconds in capture?.pause(for: seconds) },
            resume: { [weak capture] in capture?.resumeCapture() },
            clearHistory: { maintenance.confirmClearHistory() },
            openSettings: { settings.show() },
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
        capture.onPauseChange = { [weak statusItem] in statusItem?.refreshIcon() }
        languageCard.onReady = { hud.show("Translation is ready") }

        // Main shortcuts: double-tap ⌥ (clipboard) and ⌃ (translate), changeable in Settings.
        doubleTaps.onDoubleTap = { [weak popup, weak translation] modifier in
            if modifier == AppSettings.popupTap {
                popup?.toggle()
            } else if modifier == AppSettings.translateTap {
                translation?.translateSelection()
            }
        }
        doubleTaps.start()
        accessibilityCard.onGranted = { [weak self] in self?.doubleTaps.start() }
        // Optional key combos from Settings (none by default). Translation fires on key-up, so the
        // keys are released before ClipDock sends ⌘C.
        KeyboardShortcuts.onKeyDown(for: .openPopup) { [weak popup] in popup?.toggle() }
        KeyboardShortcuts.onKeyUp(for: .translate) { [weak translation] in translation?.translateSelection() }

        capture.start()
        statusItem.refreshIcon()
        warmCaches(thumbnails: thumbnails)
        DispatchQueue.main.async { popup.prewarm() }

        self.capture = capture
        self.translation = translation
        self.popup = popup
        self.settings = settings
        self.maintenance = maintenance
        self.statusItem = statusItem
        #if DEBUG
        // Test-only remote control. Off unless launched with `open --env CLIPDOCK_DEBUG_HOOKS=1`,
        // because any local process could otherwise drive pastes through ClipDock's permissions.
        if ProcessInfo.processInfo.environment["CLIPDOCK_DEBUG_HOOKS"] == "1" {
            debugHooks = DebugHooks(targets: .init(
                popup: popup, translation: translation, card: translationCard,
                settings: settings, maintenance: maintenance, capture: capture
            ))
        }
        #endif
        Log.app.notice("launched accessibility=\(AccessibilityAccess.isTrusted, privacy: .public) secureInputCheck=\(SecureInput.isAvailable, privacy: .public)")
        Log.app.notice("""
            settings popupTap=\(AppSettings.popupTap?.rawValue ?? "off", privacy: .public) \
            translateTap=\(AppSettings.translateTap?.rawValue ?? "off", privacy: .public) \
            englishInto=\(AppSettings.englishTarget.code, privacy: .public) \
            maxItems=\(AppSettings.maxUnpinnedItems, privacy: .public) \
            days=\(AppSettings.retentionDays, privacy: .public) \
            separator=\(AppSettings.pasteAllSeparator.rawValue, privacy: .public) \
            ignoredApps=\(AppSettings.ignoredBundleIDs.count, privacy: .public) \
            launchAtLogin=\(LaunchAtLogin.isEnabled, privacy: .public) \
            paused=\(capture.pausedUntil != nil, privacy: .public)
            """)

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
