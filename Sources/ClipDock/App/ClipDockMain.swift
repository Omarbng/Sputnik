import AppKit

/// App entry point. AppKit-driven so we control the menu bar and (later) the panel directly.
@main
enum ClipDockMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication.delegate is weak; keep ours alive for the life of the run loop.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
