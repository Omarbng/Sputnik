import SwiftUI

/// Explains why Sputnik needs Accessibility: to press ⌘V for you.
struct AccessibilityCardView: View {
    let onContinue: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Let Sputnik use the keyboard", systemImage: "keyboard")
                .font(.headline)
            Text("Sputnik needs the **Accessibility** permission for two things: noticing your double-tap shortcuts (⌥⌥ and ⌃⌃), and pressing ⌘V in the app you were using when you pick an item.")
            Text("Without it, the shortcuts don't work, and Sputnik only copies items, so you press ⌘V yourself.")
            Text("Click Continue, then turn on Sputnik in System Settings → Privacy & Security → Accessibility. This window closes by itself when that's done.")
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
