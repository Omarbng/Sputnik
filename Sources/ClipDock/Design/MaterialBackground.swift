import AppKit
import SwiftUI

/// The shared surface (section 5.1): a background blur under a 95%-opaque fill, a 1 pt
/// hairline border, and a large soft shadow. Used by the dock, the list card, the HUD, and
/// the translation card. Pass `cornerRadius: nil` for a capsule.
struct MaterialBackground: View {
    var cornerRadius: CGFloat?
    var shadow = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        GeometryReader { proxy in
            let radius = cornerRadius ?? min(proxy.size.width, proxy.size.height) / 2
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                BlurView(cornerRadius: radius)
                shape.fill(tokens.background.opacity(0.95))
            }
            .overlay(shape.strokeBorder(tokens.border, lineWidth: 1))
            .compositingGroup()
            .shadow(color: shadow ? tokens.shadow : .clear, radius: 24, x: 0, y: 12)
        }
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
