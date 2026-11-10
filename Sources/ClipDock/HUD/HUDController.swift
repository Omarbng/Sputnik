import AppKit
import ClipDockCore
import SwiftUI

enum HUDStyle {
    case info
    case error

    /// 600 ms for confirmations, 1.5 s for errors and fallbacks (they carry an instruction).
    var duration: Duration {
        switch self {
        case .info: .milliseconds(600)
        case .error: .milliseconds(1_500)
        }
    }
}

/// A small message pill at the cursor ("Copied", "Translating…", errors). It never takes focus.
@MainActor
final class HUDController {
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // the pill draws its own shadow
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
    }

    /// Shows `message` at the cursor. With `autoHide: false` it stays until `hide()`.
    func show(_ message: String, style: HUDStyle = .info, autoHide: Bool = true) {
        let host = NSHostingView(rootView: HUDView(message: message, style: style))
        let size = host.fittingSize
        panel.contentView = host
        let screens = NSScreen.screens.map { PopupPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        panel.setFrame(PopupPlacement.frame(size: size, cursor: NSEvent.mouseLocation, screens: screens), display: true)
        panel.orderFrontRegardless()
        Log.app.notice("hud style=\(style == .info ? "info" : "error", privacy: .public)")

        hideTask?.cancel()
        guard autoHide else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: style.duration)
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
    }
}
