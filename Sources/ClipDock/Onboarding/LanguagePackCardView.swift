import ClipDockCore
import SwiftUI
@preconcurrency import Translation

/// Asks macOS to download English and Russian once. `prepareTranslation()` needs a session
/// from SwiftUI's `.translationTask`, so the system's download prompt can attach to this window.
struct LanguagePackCardView: View {
    let onDismiss: @MainActor () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Download English and Russian", systemImage: "character.bubble")
                .font(.headline)
            Text("ClipDock translates with Apple's on-device engine, so your text never leaves this Mac. It needs the English and Russian language files once.")
            Text("Click Download, then confirm in the macOS prompt. This window closes by itself when both languages are ready.")
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Not Now", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Download") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(configuration != nil)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 420)
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                // Usually one download covers both directions. If not, ask for the other one.
                let missing = await LanguagePacks.missingDirections()
                configuration = missing.first.map { .init(source: $0.sourceLanguage, target: $0.targetLanguage) }
            } catch {
                Log.translate.error("language download failed: \(String(describing: error), privacy: .public)")
                errorMessage = "The download didn't finish. Try again."
                configuration = nil
            }
        }
    }

    private func start() {
        errorMessage = nil
        configuration = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ru"))
    }
}
