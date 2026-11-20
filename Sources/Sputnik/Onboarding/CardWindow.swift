import AppKit
import SwiftUI

/// A small titled window that hosts one onboarding card.
@MainActor
final class CardWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onClose: (() -> Void)?

    var isShowing: Bool { window != nil }

    func show(_ view: some View) {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.title = "Sputnik"
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        setContent(view)
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Replaces the card's content. Does nothing if the window isn't showing.
    func setContent(_ view: some View) {
        guard let window else { return }
        let controller = NSHostingController(rootView: AnyView(view))
        controller.sizingOptions = .preferredContentSize
        window.contentViewController = controller
    }

    func close() {
        window?.close()  // windowWillClose does the cleanup
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose?()
        // Hand focus back to the app Omar was using, so the next paste goes there.
        DispatchQueue.main.async { NSApp.deactivate() }
    }
}
