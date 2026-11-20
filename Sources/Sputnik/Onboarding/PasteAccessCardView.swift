import AppKit
import SwiftUI

/// Explains why Sputnik needs "Paste from Other Apps" set to Allow, with a button to get there.
struct PasteAccessCardView: View {
    let access: NSPasteboard.AccessBehavior
    let onContinue: @MainActor () -> Void
    let onOpenSettings: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    /// In `.default`, Sputnik isn't listed in System Settings until macOS has prompted once.
    private var needsFirstPrompt: Bool { access == .default }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Let Sputnik see what you copy", systemImage: "doc.on.clipboard")
                .font(.headline)
            Text("Sputnik keeps a history of what you copy so you can paste it again. Everything stays on this Mac.")
            Text("macOS asks before an app reads the clipboard. Unless Sputnik is set to **Allow**, you'd see that prompt every time you copy, so capture stays off until then.")
            Text(steps)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not Now", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                if needsFirstPrompt {
                    Button("Continue", action: onContinue)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings", action: onOpenSettings)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 420)
    }

    private var steps: String {
        if needsFirstPrompt {
            "Click Continue. macOS asks once whether Sputnik may paste from other apps. Allow it, and this card moves to the next step."
        } else {
            "In System Settings → Privacy & Security → Paste from Other Apps, set Sputnik to Allow. This window closes by itself when that's done."
        }
    }
}
