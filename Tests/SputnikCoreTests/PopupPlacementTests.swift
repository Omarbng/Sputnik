import CoreGraphics
import Testing
@testable import SputnikCore

@Suite("Popup placement")
struct PopupPlacementTests {
    let size = CGSize(width: 360, height: 340)
    // A 1440×900 main screen with a 25 pt menu bar and a 70 pt Dock at the bottom.
    let main = PopupPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)
    )
    // A 1920×1080 second monitor to the left, with no Dock or menu bar.
    let left = PopupPlacement.Screen(
        frame: CGRect(x: -1920, y: -100, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: -100, width: 1920, height: 1080)
    )
    // A second monitor above the main one.
    let above = PopupPlacement.Screen(
        frame: CGRect(x: 200, y: 900, width: 1280, height: 800),
        visibleFrame: CGRect(x: 200, y: 900, width: 1280, height: 775)
    )

    func place(_ x: CGFloat, _ y: CGFloat, screens: [PopupPlacement.Screen]? = nil) -> CGRect {
        PopupPlacement.frame(size: size, cursor: CGPoint(x: x, y: y), screens: screens ?? [main])
    }

    @Test("In open space it sits at the cursor, offset (+8, −8)")
    func openSpace() {
        let frame = place(500, 600)
        #expect(frame.minX == 508)
        #expect(frame.maxY == 592)
        #expect(frame.size == size)
    }

    @Test("Near the bottom it opens above the cursor")
    func flipsAbove() {
        let frame = place(500, 200)
        #expect(frame.minY == 208)
        #expect(frame.minX == 508)
    }

    @Test("Near the right edge it's pushed left to stay on-screen")
    func rightEdge() {
        #expect(place(1430, 600).maxX == 1440)
    }

    @Test("In the menu bar it's pushed down below the menu bar")
    func menuBar() {
        let frame = place(700, 890)
        #expect(frame.maxY == main.visibleFrame.maxY)
    }

    @Test("Every corner of each screen keeps the popup fully on that screen", arguments: [0, 1, 2])
    func corners(screenIndex: Int) {
        let screens = [main, left, above]
        let screen = screens[screenIndex]
        let f = screen.frame.insetBy(dx: 1, dy: 1)  // a point on a shared edge may belong to either screen
        let corners = [
            CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX - 1, y: f.minY),
            CGPoint(x: f.minX, y: f.maxY - 1), CGPoint(x: f.maxX - 1, y: f.maxY - 1),
        ]
        for corner in corners {
            let frame = PopupPlacement.frame(size: size, cursor: corner, screens: screens)
            #expect(screen.visibleFrame.contains(frame), "corner \(corner)")
        }
    }

    @Test("A grid of cursor positions never leaves the visible frame")
    func grid() {
        for x in stride(from: 0, through: 1440, by: 60) {
            for y in stride(from: 0, through: 900, by: 50) {
                #expect(main.visibleFrame.contains(place(CGFloat(x), CGFloat(y))))
            }
        }
    }

    @Test("On a second monitor (negative coordinates) it uses that monitor")
    func secondMonitor() {
        let frame = place(-1000, 400, screens: [main, left])
        #expect(left.visibleFrame.contains(frame))
        #expect(frame.minX == -992)
    }

    @Test("A cursor outside every screen goes to the nearest one")
    func nearestScreen() {
        let frame = place(1600, 450, screens: [main, left])
        #expect(main.visibleFrame.contains(frame))
    }
}
