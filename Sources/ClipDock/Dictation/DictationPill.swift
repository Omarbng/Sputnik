import AppKit
import ClipDockCore
import Observation
import SwiftUI

/// What the pill shows while dictating.
@MainActor
@Observable
final class PillState {
    enum Phase: Equatable {
        case listening
        case working(String)  // "Transcribing…", "Polishing…", "Translating…"
    }

    var phase = Phase.listening
    var mode = DictationMode.dictate
    var handsFree = false
    /// 0…1 microphone level.
    var level: Float = 0
    /// The live text (its end), never logged.
    var preview = ""
}

/// The dictation pill: a small capsule near the bottom of the screen with the mouse (where
/// Wispr Flow shows its own), in the dock's material. It never takes focus, so typing and the
/// paste still go to the app Omar is in.
@MainActor
final class DictationPill {
    let state = PillState()
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: DictationPillView(state: state))
        host.sizingOptions = []
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        let size = CGSize(width: DictationPillView.width + DictationPillView.margin * 2, height: DictationPillView.height + DictationPillView.margin * 2)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 56 - DictationPillView.margin)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        fade(to: 1)
    }

    func hide() {
        guard panel.isVisible else { return }
        fade(to: 0) { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
            self.state.preview = ""
            self.state.level = 0
        }
    }

    private func fade(to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0.12 : 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    #if DEBUG
    /// Debug snapshot of the pill (screenshots need Screen Recording).
    func snapshot(to path: String) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif
}

struct DictationPillView: View {
    static let width: CGFloat = 300
    static let height: CGFloat = 40
    static let margin: CGFloat = 32

    let state: PillState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        HStack(spacing: 10) {
            LevelMeter(level: state.phase == .listening ? state.level : 0, color: tokens.foreground)
                .frame(width: 26, height: 18)
            Text(line)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.13)
                .foregroundStyle(state.preview.isEmpty || state.phase != .listening ? tokens.mutedForeground : tokens.foreground)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let chip {
                Text(chip)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.primaryForeground)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(tokens.primary, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .frame(width: Self.width, height: Self.height)
        .background(MaterialBackground(cornerRadius: nil))
        .padding(Self.margin)
    }

    private var line: String {
        switch state.phase {
        case .working(let status): return status
        case .listening:
            if !state.preview.isEmpty { return state.preview }
            return state.handsFree ? "Listening — fn to finish, esc to cancel" : "Listening…"
        }
    }

    private var chip: String? {
        switch state.mode {
        case .dictate: state.handsFree ? "Hands-free" : nil
        case .command: "Command"
        case .translate: "Translate"
        }
    }
}

/// Five bars that follow the microphone level, the middle ones tallest.
private struct LevelMeter: View {
    let level: Float
    let color: Color
    private static let shape: [CGFloat] = [0.45, 0.75, 1, 0.75, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: max(3, 18 * CGFloat(level) * Self.shape[index]))
            }
        }
        .animation(.interpolatingSpring(mass: 0.4, stiffness: 600, damping: 30), value: level)
    }
}
