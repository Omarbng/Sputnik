import AppKit
import SwiftUI

/// The shared surface (section 5.1): a background blur under a 95%-opaque fill, a 1 pt
/// hairline border, and a large soft shadow. Used by the dock, the list card, the HUD, and
/// the translation card. Pass `cornerRadius: nil` for a capsule.
///
/// Polish (2026-11-19): a faint highlight along the top edge, so the surface reads as one
/// machined piece rather than a flat cut-out, and the shadow is two layers (a wide, soft
/// ambient one plus a tight contact one) instead of a single dark drop shadow. Capsules use
/// circular ends: the continuous-curve capsule drew stray hairlines past its ends.
struct MaterialBackground: View {
    var cornerRadius: CGFloat?
    var shadow = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        let dark = scheme == .dark
        GeometryReader { proxy in
            let isCapsule = cornerRadius == nil
            let radius = cornerRadius ?? min(proxy.size.width, proxy.size.height) / 2
            let shape = RoundedRectangle(cornerRadius: radius, style: isCapsule ? .circular : .continuous)
            ZStack {
                BlurView(cornerRadius: radius)
                shape.fill(tokens.background.opacity(0.95))
            }
            .overlay(shape.strokeBorder(tokens.border, lineWidth: 1))
            .overlay(
                shape
                    .inset(by: 1)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(dark ? 0.07 : 0.8), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: min(0.5, 24 / max(proxy.size.height, 1)))
                        ),
                        lineWidth: 1
                    )
            )
            .compositingGroup()
            .shadow(color: shadow ? .black.opacity(dark ? 0.34 : 0.10) : .clear, radius: 26, x: 0, y: 14)
            .shadow(color: shadow ? .black.opacity(dark ? 0.22 : 0.06) : .clear, radius: 1.5, x: 0, y: 1)
        }
    }
}

/// Buttons that press in slightly, like a physical key (and spring back).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduceMotion ? scale : 1)
            .animation(.interpolatingSpring(mass: 0.4, stiffness: 600, damping: 28), value: configuration.isPressed)
    }
}

/// Behind-window blur, clipped with a mask image, because a SwiftUI clip shape doesn't clip
/// the window-server blur.
private struct BlurView: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if context.coordinator.radius != cornerRadius {
            context.coordinator.radius = cornerRadius
            view.maskImage = Self.mask(radius: cornerRadius)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(radius: cornerRadius) }

    final class Coordinator {
        var radius: CGFloat
        init(radius: CGFloat) { self.radius = radius }
    }

    /// A stretchable rounded rectangle, so any size keeps the same corners.
    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
