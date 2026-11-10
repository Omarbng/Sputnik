import SwiftUI

/// Explains why ClipDock needs Accessibility: to press ⌘V for you.
struct AccessibilityCardView: View {
    let onContinue: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Let ClipDock paste for you", systemImage: "keyboard")
                .font(.headline)
            Text("When you pick an item, ClipDock puts it on the clipboard and presses ⌘V in the app you were using. macOS needs the **Accessibility** permission for that.")
            Text("Without it, ClipDock still copies the item, and you press ⌘V yourself.")
            Text("Click Continue, then turn on ClipDock in System Settings → Privacy & Security → Accessibility. This window closes by itself when that's done.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not Now", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 420)
    }
}
