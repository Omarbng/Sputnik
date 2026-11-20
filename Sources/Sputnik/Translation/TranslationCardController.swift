import AppKit
import SputnikCore
import SwiftUI

/// The translation card at the cursor (double-tap ⌃). ↩ replaces the selected text, ⌘C copies
/// the translation, and Esc, a click outside, or losing focus closes it.
@MainActor
final class TranslationCardController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 380
    static let maxTextHeight: CGFloat = 260

    private let panel = PopupPanel()
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var onCopy: (() -> Void)?
    private var onReplace: (() -> Void)?

    override init() {
        super.init()
        panel.delegate = self
    }

    func show(
        translation: String, direction: TranslationDirection, note: String = "", primaryTitle: String = "Replace",
        onReplace: @escaping () -> Void, onCopy: @escaping () -> Void
    ) {
        self.onCopy = onCopy
        self.onReplace = onReplace
        let textHeight = min(Self.textHeight(translation), Self.maxTextHeight)
        let host = NSHostingView(rootView: TranslationCardView(
            text: translation,
            direction: direction,
            note: note,
            primaryTitle: primaryTitle,
            textHeight: textHeight,
            onReplace: { [weak self] in self?.replace() },
            onCopy: { [weak self] in self?.copyTranslation() }
        ))
        let size = host.fittingSize
        panel.contentView = host
        panel.hasShadow = false  // the card draws its own shadow
        let margin = TranslationCardView.shadowMargin
        let card = CGSize(width: size.width - margin * 2, height: size.height - margin * 2)
        let screens = NSScreen.screens.map { PopupPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let frame = PopupPlacement.frame(size: card, cursor: NSEvent.mouseLocation, screens: screens)
        panel.setFrame(frame.insetBy(dx: -margin, dy: -margin), display: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() {
        removeMonitors()
        panel.orderOut(nil)
    }

    #if DEBUG
    /// Debug snapshot (screenshots need Screen Recording).
    func snapshot(to path: String) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// Debug hooks press the card's buttons through this.
    func perform(_ command: PopupCommand) {
        switch command {
        case .pasteSelected: replace()
        case .copySelected: copyTranslation()
        case .close: close()
        default: break
        }
    }

    private func copyTranslation() {
        onCopy?()
        close()
    }

    /// Close first, so focus goes back to the app that still has the selection.
    private func replace() {
        let action = onReplace
        close()
        action?()
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                switch PopupKeymap.command(keyCode: event.keyCode, modifiers: .init(event.modifierFlags)) {
                case .close?: self.close()
                case .copySelected?: self.copyTranslation()
                case .pasteSelected?: self.replace()
                default: return false
                }
                return true
            }
            return handled ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private static func textHeight(_ text: String) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width - 28, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        return ceil(bounds.height) + 4
    }
}

/// The show-only card: the dock's material, 18 pt corners, the direction, the translation, and
/// a Copy button with its keycaps.
struct TranslationCardView: View {
    static let shadowMargin: CGFloat = 40  // the two-layer shadow reaches 40 pt below

    let text: String
    let direction: TranslationDirection
    /// "from clipboard", "reply" …
    let note: String
    /// "Replace" over a selection, "Paste" when the text came from the clipboard.
    let primaryTitle: String
    let textHeight: CGFloat
    let onReplace: () -> Void
    let onCopy: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tokens = Tokens.for(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // An eyebrow chip: the direction, and "from clipboard" / "reply" when they apply.
                Text((note.isEmpty ? direction.label : "\(direction.label) · \(note)").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(tokens.mutedForeground)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(tokens.accent, in: Capsule())
                Spacer()
                Text("Esc to close")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.mutedForeground)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.foreground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: textHeight)
            HStack(spacing: 8) {
                Spacer()
                cardButton("Copy", keys: "⌘C", tokens: tokens, prominent: false, action: onCopy)
                cardButton(primaryTitle, keys: "↩", tokens: tokens, prominent: true, action: onReplace)
            }
        }
        .padding(16)
        .frame(width: TranslationCardController.width)
        .background(MaterialBackground(cornerRadius: PopupLayout.cardCornerRadius))
        .padding(Self.shadowMargin)
    }

    /// Replace is the inverted (primary) button, Copy the quiet one. Each key sits in its own
    /// small capsule, flush with the button's right end (a button within the button), and the
    /// button presses in slightly when clicked.
    private func cardButton(_ title: String, keys: String, tokens: Tokens, prominent: Bool, action: @escaping () -> Void) -> some View {
        let ink = prominent ? tokens.primaryForeground : tokens.foreground
        return Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .medium)).tracking(-0.13)
                Text(keys)
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.75)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(ink.opacity(0.1), in: Capsule())
            }
            .foregroundStyle(ink)
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .frame(height: 30)
            .background(prominent ? tokens.primary : tokens.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
