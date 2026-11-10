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

/// A small message pill at the cursor ("Copied", "Translating…", errors), in the same
/// material as the dock (section 5.4). It never takes focus, and it fades in and out over 180 ms
/// (120 ms with Reduce Motion).
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
        // Place the pill itself at the cursor; the panel adds a margin for its shadow.
        let margin = HUDView.shadowMargin
        let pill = CGSize(width: size.width - margin * 2, height: size.height - margin * 2)
        let screens = NSScreen.screens.map { PopupPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let frame = PopupPlacement.frame(size: pill, cursor: NSEvent.mouseLocation, screens: screens)
        panel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        fade(to: 1)
        Log.app.notice("hud style=\(style == .info ? "info" : "error", privacy: .public)")

        hideTask?.cancel()
        guard autoHide else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: style.duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        guard panel.isVisible else { return }
        fade(to: 0) { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        }
    }

    private func fade(to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        let reduce = Motion.reduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0.12 : 0.18
            context.timingFunction = reduce
                ? CAMediaTimingFunction(name: .easeInEaseOut)
                : CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }
}
