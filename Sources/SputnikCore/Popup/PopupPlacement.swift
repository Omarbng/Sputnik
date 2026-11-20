import CoreGraphics

/// Where the popup goes. It opens at the cursor offset by (+8, −8), on the screen under the
/// cursor, fully inside that screen's visible frame. If there's no room below the cursor, it
/// opens above it. Coordinates are AppKit global coordinates (origin bottom-left, y up).
public enum PopupPlacement {
    public struct Screen: Sendable, Equatable {
        public var frame: CGRect
        public var visibleFrame: CGRect

        public init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    public static let gap: CGFloat = 8

    public static func frame(size: CGSize, cursor: CGPoint, screens: [Screen]) -> CGRect {
        guard let screen = screen(containing: cursor, in: screens) else {
            return CGRect(origin: cursor, size: size)
        }
        let area = screen.visibleFrame

        var x = cursor.x + gap
        // Below the cursor: the popup's top edge sits `gap` under it.
        var y = cursor.y - gap - size.height
        if y < area.minY {
            // Not enough room below: the popup's bottom edge sits `gap` over the cursor.
            y = cursor.y + gap
        }

        x = max(area.minX, min(x, area.maxX - size.width))
        y = max(area.minY, min(y, area.maxY - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The screen whose frame contains the point (edges included), or else the nearest screen.
    static func screen(containing point: CGPoint, in screens: [Screen]) -> Screen? {
        if let hit = screens.first(where: { contains($0.frame, point) }) {
            return hit
        }
        return screens.min { distanceSquared($0.frame, point) < distanceSquared($1.frame, point) }
    }

    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func distanceSquared(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
