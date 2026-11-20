import AppKit
import SwiftUI

/// The Settings window (⌘, in the popup, or Settings… in the menu).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model = SettingsModel()
    private let icons: AppIconCache
    private let actions: SettingsView.Actions
    private let languagesMissing: () -> Bool
    private var window: NSWindow?
    private var timer: Timer?

    /// Called on close with whether the history limits changed.
    var onClose: ((_ limitsChanged: Bool) -> Void)?

    var isShowing: Bool { window != nil }

    init(icons: AppIconCache, actions: SettingsView.Actions, languagesMissing: @escaping () -> Bool) {
        self.icons = icons
        self.actions = actions
        self.languagesMissing = languagesMissing
    }

    func show() {
        model.reload(languagesMissing: languagesMissing())
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model, icons: icons, actions: actions))
            let window = NSWindow(contentViewController: controller)
            window.title = "Sputnik Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        startRefreshing()
        Log.app.notice("settings opened")
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        window = nil
        onClose?(model.consumeLimitsChanged())
        Log.app.notice("settings closed")
        // Hand focus back to the app Omar was using, so the next paste goes there.
        DispatchQueue.main.async { NSApp.deactivate() }
    }

    /// Keeps the permission rows current while the window is open.
    private func startRefreshing() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.refreshStatus(languagesMissing: self.languagesMissing())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
