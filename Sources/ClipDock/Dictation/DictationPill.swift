import AppKit
import ClipDockCore
import Observation
import SwiftUI

/// What the pill shows while dictating. No words, only the dots (Omar, 2026-11-19: "just a
/// clean bar with the dots in the middle").
@MainActor
@Observable
final class PillState {
    enum Phase: Equatable {
        /// The dots follow the voice.
        case listening
        /// Recognising, polishing or translating: the dots ripple.
        case working
    }

    var phase = Phase.listening
    /// fn + ⌃ and fn + ⇧ tint the dots, so a mode shows without a label.
    var mode = DictationMode.dictate
    /// 0…1 microphone level.
    var level: Float = 0
    /// Drives the spring in and out.
    var isShown = false
}

/// The dictation pill: a small bar near the bottom of the screen with the mouse (where Wispr
/// Flow shows its own). It never takes focus, so typing and the paste go to the app Omar is in.
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
        let margin = DictationPillView.shadowMargin
        let size = CGSize(width: DictationPillView.size.width + margin * 2, height: DictationPillView.size.height + margin * 2)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(), y: visible.minY + 48 - margin)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        state.isShown = true
        fade(to: 1, duration: 0.22)
    }

    func hide() {
        guard panel.isVisible else { return }
        state.isShown = false
        fade(to: 0, duration: 0.2) { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
            self.state.level = 0
            self.state.phase = .listening
            self.state.mode = .dictate
        }
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.reduceMotion ? 0.12 : duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
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

/// A machined bar: an outer shell with a hairline edge, holding an inner core
/// with a soft top highlight, so it reads as one physical piece. Inside, only the five dots.
struct DictationPillView: View {
    static let size = CGSize(width: 108, height: 36)
    /// Inset of the inner core inside the shell (the "bezel").
    static let bezel: CGFloat = 3
    /// Transparent room for the shadow.
    static let shadowMargin: CGFloat = 36

    let state: PillState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let reduce = Motion.reduceMotion
        ZStack {
            shell
            core
            DotMeter(state: state, color: dotColor, reduceMotion: reduce)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(state.isShown || reduce ? 1 : 0.9)
        .animation(reduce ? nil : .interpolatingSpring(mass: 0.6, stiffness: 520, damping: 26), value: state.isShown)
        .padding(Self.shadowMargin)
    }

    private var isDark: Bool { scheme == .dark }

    /// Outer shell: a near-solid capsule with a hairline edge (a bar this small gains nothing
    /// from blur, and the window blur's mask doesn't follow a capsule's ends cleanly), lifted by
    /// a two-layer, widely diffused shadow instead of one dark drop shadow. Circular ends: the
    /// continuous-curve capsule drew stray hairlines past its ends.
    private var shell: some View {
        let tokens = Tokens.for(scheme)
        return Capsule(style: .circular)
            .fill(tokens.background.opacity(isDark ? 0.94 : 0.97))
            .overlay(Capsule(style: .circular).strokeBorder(tokens.border, lineWidth: 1))
            .shadow(color: .black.opacity(isDark ? 0.32 : 0.10), radius: 18, x: 0, y: 10)
            .shadow(color: .black.opacity(isDark ? 0.20 : 0.06), radius: 2, x: 0, y: 1)
    }

    /// Inner core: a touch lighter than the shell, with a highlight along its top edge.
    private var core: some View {
        Capsule(style: .circular)
            .fill(isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.025))
            .overlay(
                Capsule(style: .circular).strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(isDark ? 0.16 : 0.9), Color.white.opacity(0)],
                        startPoint: .top, endPoint: .center
                    ),
                    lineWidth: 1
                )
            )
            .padding(Self.bezel)
    }

    /// Plain dictation uses the text colour; a command is amber, a translation is blue.
    private var dotColor: Color {
        let tokens = Tokens.for(scheme)
        return switch state.mode {
        case .dictate: tokens.foreground
        case .command: Color(hex: isDark ? 0xF4C26B : 0xC98A12)
        case .translate: Color(hex: isDark ? 0x8CCBFF : 0x2F7FD1)
        }
    }
}

/// Five dots in the middle of the bar. At rest they're round; while listening they stretch
/// with the voice (the centre ones most); while working they ripple from left to right.
private struct DotMeter: View {
    let state: PillState
    let color: Color
    let reduceMotion: Bool

    static let dot: CGFloat = 4
    static let gap: CGFloat = 4
    static let maxHeight: CGFloat = 18
    private static let weights: [CGFloat] = [0.5, 0.8, 1, 0.8, 0.5]

    var body: some View {
        if state.phase == .working, !reduceMotion {
            TimelineView(.animation) { context in
                dots { index in Self.ripple(index, at: context.date.timeIntervalSinceReferenceDate) }
            }
        } else {
            dots { index in
                let level = state.phase == .listening ? CGFloat(state.level) : 0
                return (height: Self.dot + (Self.maxHeight - Self.dot) * level * Self.weights[index],
                        opacity: 0.55 + 0.45 * min(level * 1.6, 1))
            }
            .animation(reduceMotion ? nil : .interpolatingSpring(mass: 0.35, stiffness: 520, damping: 22), value: state.level)
        }
    }

    private func dots(_ shape: @escaping (Int) -> (height: CGFloat, opacity: Double)) -> some View {
        HStack(alignment: .center, spacing: Self.gap) {
            ForEach(0..<5, id: \.self) { index in
                let look = shape(index)
                Capsule(style: .circular)
                    .fill(color)
                    .frame(width: Self.dot, height: look.height)
                    .opacity(look.opacity)
            }
        }
        .frame(height: Self.maxHeight)
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: color)
    }

    /// A soft travelling wave, about one pass a second.
    private static func ripple(_ index: Int, at time: TimeInterval) -> (height: CGFloat, opacity: Double) {
        let phase = sin(time * 2 * .pi * 1.1 - Double(index) * 0.7)
        let lift = (phase + 1) / 2  // 0…1
        return (height: dot + 6 * CGFloat(lift), opacity: 0.45 + 0.55 * lift)
    }
}
