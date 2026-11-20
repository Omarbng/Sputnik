import AVFoundation
import AppKit
import SputnikCore
import Observation
import SwiftUI

/// The first-launch setup, "Welcome to Sputnik": what it does, your languages, the three
/// permissions, then the downloads and keys. Shown once on a new Mac (a Mac that ran ClipDock
/// keeps its settings and skips it); Settings → General → Run Setup Again… reopens it.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    struct Actions {
        var allowKeyboard: () -> Void
        var allowClipboard: () -> Void
        var downloadTranslation: () -> Void
        var openShortcuts: () -> Void
        var finished: () -> Void
    }

    private let model: SetupModel
    private var window: NSWindow?
    private var timer: Timer?

    init(actions: Actions) {
        model = SetupModel(actions: actions)
        super.init()
        model.close = { [weak self] in self?.window?.close() }
    }

    var isShowing: Bool { window != nil }

    func show() {
        model.start()
        if window == nil {
            let host = NSHostingController(rootView: SetupView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "Welcome to Sputnik"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        startRefreshing()
        Log.app.notice("setup opened step=\(self.model.step.rawValue, privacy: .public)")
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        window = nil
        // Closing it early still counts: the menu bar and Settings have everything.
        model.finish()
        DispatchQueue.main.async { NSApp.deactivate() }
    }

    /// Permissions and downloads change outside the app; re-check while the window is open.
    private func startRefreshing() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshPermissions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    #if DEBUG
    /// Tests: go to a step ("welcome", "languages", "permissions", "ready") and render it.
    func show(step: String) {
        show()
        if let step = SetupModel.Step(rawValue: step) { model.step = step }
    }

    func snapshot(to path: String) {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif
}

@MainActor
@Observable
final class SetupModel {
    enum Step: String, CaseIterable {
        case welcome, languages, permissions, ready
    }

    var step = Step.welcome
    let languages = LanguagesModel()
    private(set) var keyboardAllowed = AccessibilityAccess.isTrusted
    private(set) var clipboardAllowed = PasteboardAccess.behavior == .alwaysAllow
    private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @ObservationIgnored let actions: SetupWindowController.Actions
    @ObservationIgnored var close: () -> Void = {}
    @ObservationIgnored private var finished = false

    init(actions: SetupWindowController.Actions) {
        self.actions = actions
    }

    func start() {
        finished = false
        languages.reload()
        refreshPermissions()
    }

    func refreshPermissions() {
        keyboardAllowed = AccessibilityAccess.isTrusted
        clipboardAllowed = PasteboardAccess.behavior == .alwaysAllow
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        if step == .ready { languages.refresh() }
    }

    var stepNumber: Int { (Step.allCases.firstIndex(of: step) ?? 0) + 1 }

    func next() {
        guard let index = Step.allCases.firstIndex(of: step) else { return }
        if index + 1 < Step.allCases.count {
            step = Step.allCases[index + 1]
            if step == .ready { languages.refresh() }
        } else {
            close()  // finish() runs as the window closes
        }
    }

    func back() {
        guard let index = Step.allCases.firstIndex(of: step), index > 0 else { return }
        step = Step.allCases[index - 1]
    }

    func allowMicrophone() {
        if microphone == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        AppSettings.didCompleteSetup = true
        Log.app.notice("setup finished step=\(self.step.rawValue, privacy: .public)")
        actions.finished()
    }
}

/// The setup's pages, in the app's own look: an eyebrow with the step, a title, the content,
/// and Back / Continue at the bottom.
struct SetupView: View {
    @Bindable var model: SetupModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STEP \(model.stepNumber) OF \(SetupModel.Step.allCases.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(tokens.mutedForeground)
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 10)

            Group {
                switch model.step {
                case .welcome: welcome(tokens)
                case .languages: languages
                case .permissions: permissions
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack {
                if model.step != .welcome {
                    Button("Back") { model.back() }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(model.step == .ready ? "Start Using Sputnik" : (model.step == .welcome ? "Get Started" : "Continue")) {
                    model.next()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 560, height: 600)
        .background(tokens.background)
        .animation(Motion.reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: model.step)
    }

    private var title: String {
        switch model.step {
        case .welcome: "Welcome to Sputnik"
        case .languages: "Your languages"
        case .permissions: "Three permissions"
        case .ready: "Ready"
        }
    }

    private var subtitle: String {
        switch model.step {
        case .welcome: "Your clipboard, your voice and translation, at your cursor. Everything runs on this Mac."
        case .languages: "Pick the language you write in, the ones you read, and the ones you speak. You can change this any time in Settings."
        case .permissions: "macOS asks before an app can use the keyboard, the clipboard or the microphone. Sputnik only uses them while you use it."
        case .ready: "Apple's language files download once, then everything works offline."
        }
    }

    // MARK: Pages

    private func welcome(_ tokens: Tokens) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            feature("doc.on.clipboard", "Clipboard history at your cursor", "Tap ⌥ twice. Search, paste, save snippets, keep secrets behind Touch ID.", tokens)
            feature("mic", "Talk instead of typing", "Hold fn, speak, let go: it's typed where you are.", tokens)
            feature("character.bubble", "Translate and proofread anywhere", "Select text: tap ⌃ twice to translate, ⇧ twice to proofread.", tokens)
            feature("lock.shield", "Private by design", "No account, no cloud, no tracking. Apple's on-device engines do the work.", tokens)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String, _ tokens: Tokens) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tokens.foreground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tokens.accent))
                .overlay(Circle().strokeBorder(tokens.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(tokens.foreground)
                Text(detail).font(.system(size: 13)).foregroundStyle(tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var languages: some View {
        Form {
            Section("Translation") {
                TranslationLanguageRows(languages: model.languages)
            }
            Section("Dictation: languages you speak") {
                SpokenLanguageRows(languages: model.languages)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var permissions: some View {
        Form {
            Section {
                permissionRow("keyboard", "Keyboard (Accessibility)",
                              "For the double-tap shortcuts, fn, and pasting into the app you're in.",
                              ok: model.keyboardAllowed, action: model.actions.allowKeyboard)
                permissionRow("doc.on.clipboard", "Clipboard (Paste from Other Apps)",
                              "To keep a history of what you copy. Choose Allow.",
                              ok: model.clipboardAllowed, action: model.actions.allowClipboard)
                permissionRow("mic", "Microphone",
                              "Only while you hold fn. The audio never leaves memory.",
                              ok: model.microphone == .authorized, action: model.allowMicrophone)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func permissionRow(_ symbol: String, _ title: String, _ detail: String, ok: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if ok {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .help("Allowed")
            } else {
                Button("Allow…", action: action)
            }
        }
        .padding(.vertical, 2)
    }

    private var ready: some View {
        Form {
            Section("Downloads") {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Translation")
                        Text(ListFormatter.localizedString(byJoining: model.languages.setup.all.map(\.name)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.languages.translationFilesMissing {
                        Button("Download…", action: model.actions.downloadTranslation)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                SpokenLanguageRows(languages: model.languages)
            }
            Section("Keys to remember") {
                keyRow(["⌥", "⌥"], "Clipboard history")
                keyRow(["fn"], "Hold to talk")
                keyRow(["⌃", "⌃"], "Translate the selection")
                keyRow(["⇧", "⇧"], "Proofread the selection")
                Button("Show All Shortcuts") { model.actions.openShortcuts() }
                    .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func keyRow(_ keys: [String], _ title: String) -> some View {
        HStack(spacing: 12) {
            Keycaps(keys: keys, color: .primary).frame(width: 60, alignment: .leading)
            Text(title)
        }
    }
}
