import AppKit
import ClipDockCore
import SwiftUI

/// Menu bar → Shortcuts…: every key and voice command on one page, as currently set up.
@MainActor
final class GuideWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var host: NSHostingController<GuideView>?

    var onOpenSettings: (() -> Void)?

    func show() {
        let view = GuideView(sections: ShortcutGuide.sections(Self.options), openSettings: { [weak self] in
            self?.window?.close()
            self?.onOpenSettings?()
        })
        if let host {
            host.rootView = view
        } else {
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Shortcuts"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.host = host
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Log.app.notice("guide opened")
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Hand focus back to the app Omar was using.
        DispatchQueue.main.async { NSApp.deactivate() }
    }

    private static var options: ShortcutGuide.Options {
        ShortcutGuide.Options(
            popupTap: AppSettings.popupTap,
            translateTap: AppSettings.translateTap,
            proofreadTap: AppSettings.proofreadTap,
            dictation: AppSettings.isOn(.dictation),
            rightOption: AppSettings.isOn(.rightOptionTalk),
            sayLanguage: AppSettings.isOn(.sayLanguage),
            voiceCommands: AppSettings.isOn(.voiceCommands),
            languages: AppSettings.languages
        )
    }

    #if DEBUG
    func snapshot(to path: String) {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif
}

/// The guide: a section per area, each a card of rows (keycaps, what it does, a short how).
struct GuideView: View {
    let sections: [ShortcutGuide.Section]
    let openSettings: () -> Void
    @Environment(\.colorScheme) private var scheme

    static let keyColumn: CGFloat = 104

    var body: some View {
        let tokens = Tokens.for(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        eyebrow(section.title, tokens: tokens)
                        card(section, tokens: tokens)
                    }
                }
                HStack(spacing: 4) {
                    Text("Change keys and switch features on or off in")
                        .foregroundStyle(tokens.mutedForeground)
                    Button("Settings", action: openSettings)
                        .buttonStyle(.link)
                }
                .font(.system(size: 12))
                .padding(.leading, 4)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(width: 500, height: 640)
        .background(tokens.background)
    }

    /// A small uppercase label above each card.
    private func eyebrow(_ title: String, tokens: Tokens) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(tokens.mutedForeground)
            .padding(.leading, 4)
    }

    /// Outer shell with a hairline, inner core with a soft top highlight (the same machined
    /// look as the popup and the dictation pill).
    private func card(_ section: ShortcutGuide.Section, tokens: Tokens) -> some View {
        let dark = scheme == .dark
        return VStack(spacing: 0) {
            ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(tokens.border).frame(height: 1).padding(.leading, Self.keyColumn + 14)
                }
                rowView(row, tokens: tokens)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(dark ? Color.white.opacity(0.035) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(dark ? 0.09 : 0.9), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                )
        )
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(dark ? Color.white.opacity(0.025) : Color.black.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tokens.border, lineWidth: 1))
        )
    }

    private func rowView(_ row: ShortcutGuide.Row, tokens: Tokens) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Keycaps(keys: row.keys, color: tokens.foreground)
                .frame(width: Self.keyColumn, alignment: .leading)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
