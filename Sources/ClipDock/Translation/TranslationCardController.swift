import AppKit
import ClipDockCore
import SwiftUI

/// The show-only (⇧⌥⌘T) result: a small card at the cursor with a Copy button.
/// Esc, a click outside, or losing focus closes it.
@MainActor
final class TranslationCardController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 380
    static let maxTextHeight: CGFloat = 260

    private let panel = PopupPanel()
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var onCopy: (() -> Void)?

    override init() {
        super.init()
        panel.delegate = self
    }

    func show(translation: String, direction: TranslationDirection, onCopy: @escaping () -> Void) {
        self.onCopy = onCopy
        let textHeight = min(Self.textHeight(translation), Self.maxTextHeight)
        let host = NSHostingView(rootView: TranslationCardView(
            text: translation,
            direction: direction,
            textHeight: textHeight,
            onCopy: { [weak self] in self?.copyTranslation() }
        ))
        let size = host.fittingSize
        panel.contentView = host
        let screens = NSScreen.screens.map { PopupPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        panel.setFrame(PopupPlacement.frame(size: size, cursor: NSEvent.mouseLocation, screens: screens), display: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() {
        removeMonitors()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func copyTranslation() {
        onCopy?()
        close()
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                switch PopupKeymap.command(keyCode: event.keyCode, modifiers: .init(event.modifierFlags)) {
                case .close?: self.close()
                case .copySelected?: self.copyTranslation()
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

struct TranslationCardView: View {
    let text: String
    let direction: TranslationDirection
    let textHeight: CGFloat
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(direction.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Esc to close")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: textHeight)
            HStack {
                Spacer()
                Button("Copy", action: onCopy)
            }
        }
        .padding(14)
        .frame(width: TranslationCardController.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1)))
    }
}
