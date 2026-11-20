// Test helper for ClipDock M2 (scratchpad only, not part of the app).
//   cdtool layout-get | layout-set <id> | layout-list
//   cdtool mouse-get | mouse-set <x> <y>          (top-left-origin screen coordinates)
//   cdtool screens                                 (AppKit frames, for corner tests)
//   cdtool target <outfile> [secure] [--text <file>]
//        Paste target window. It writes its text to <outfile> on every change. With --text it
//        starts with that text, all selected. It undoes on the distributed notification
//        "com.omar.clipdock.testtarget.undo". Launch it as an app (Tools/README.md) so it comes
//        to the front.
import AppKit
import Carbon

func sources() -> [TISInputSource] {
    let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
    return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
}
func sourceID(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "layout-get":
    print(sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
case "layout-list":
    sources().forEach { print(sourceID($0)) }
case "layout-set":
    guard let s = sources().first(where: { sourceID($0) == args[2] }) else { print("not enabled"); exit(1) }
    print(TISSelectInputSource(s) == noErr ? "ok" : "failed")
case "mouse-get":
    let p = CGEvent(source: nil)!.location
    print("\(Int(p.x)) \(Int(p.y))")
case "mouse-set":
    CGWarpMouseCursorPosition(CGPoint(x: Double(args[2])!, y: Double(args[3])!))
    CGAssociateMouseAndMouseCursorPosition(1)
case "screens":
    for s in NSScreen.screens { print(NSStringFromRect(s.frame), NSStringFromRect(s.visibleFrame)) }
case "target":
    let out = args[2]
    let secure = args.contains("secure")
    let initial = args.firstIndex(of: "--text").flatMap { try? String(contentsOfFile: args[$0 + 1], encoding: .utf8) }
    final class Target: NSObject, NSApplicationDelegate, NSTextViewDelegate {
        let out: String; let secure: Bool; let initial: String?
        var window: NSWindow!; var text: NSTextView!
        init(out: String, secure: Bool, initial: String?) { self.out = out; self.secure = secure; self.initial = initial }
        func applicationDidFinishLaunching(_ n: Notification) {
            window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 420, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
            window.title = secure ? "ClipDock test target (secure input)" : "ClipDock test target"
            let scroll = NSTextView.scrollableTextView()
            text = (scroll.documentView as! NSTextView); text.delegate = self
            text.allowsUndo = true
            if let initial { text.string = initial; text.selectAll(nil) }
            DistributedNotificationCenter.default().addObserver(forName: .init("com.omar.clipdock.testtarget.undo"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.text.undoManager?.undo(); self?.save() }
            }
            window.contentView = scroll
            window.makeKeyAndOrderFront(nil); window.makeFirstResponder(text)
            NSApp.activate(ignoringOtherApps: true)
            if secure {
                typealias Fn = @convention(c) () -> Int32
                if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "EnableSecureEventInput") { _ = unsafeBitCast(sym, to: Fn.self)() }
            }
            save()
        }
        func textDidChange(_ n: Notification) { save() }
        func save() { try? text.string.write(toFile: out, atomically: true, encoding: .utf8) }
    }
    let app = NSApplication.shared
    // ⌘C/⌘V/⌘Z reach a text view only through the Edit menu's key equivalents.
    let mainMenu = NSMenu()
    let appItem = NSMenuItem(); appItem.submenu = NSMenu(); mainMenu.addItem(appItem)
    let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit"); editItem.submenu = edit; mainMenu.addItem(editItem)
    for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
        edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
    }
    app.mainMenu = mainMenu
    let delegate = Target(out: out, secure: secure, initial: initial)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    signal(SIGTERM) { _ in exit(0) }   // exiting ends secure input automatically
    app.run()
default:
    print("usage: see header"); exit(2)
}
