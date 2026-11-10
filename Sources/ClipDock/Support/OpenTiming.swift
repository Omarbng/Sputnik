import Foundation
import os

private let popupSignposter = OSSignposter(subsystem: "com.omar.clipdock", category: "popup")

/// Measures shortcut → popup on screen. Signposted for Instruments, logged, and printed in
/// debug builds. Target: under 100 ms.
struct OpenTiming {
    private let state: OSSignpostIntervalState
    private let start: ContinuousClock.Instant

    init() {
        start = .now
        state = popupSignposter.beginInterval("open")
    }

    /// Call right after ordering the panel front. Finishes on the next main-loop turn, after
    /// AppKit has displayed the panel.
    func finish() {
        let state = state
        let start = start
        DispatchQueue.main.async {
            popupSignposter.endInterval("open", state)
            let ms = (ContinuousClock.now - start) / .milliseconds(1)
            Log.popup.notice("open ms=\(ms, format: .fixed(precision: 1), privacy: .public)")
            #if DEBUG
            print(String(format: "ClipDock popup open: %.1f ms", ms))
            #endif
        }
    }
}
