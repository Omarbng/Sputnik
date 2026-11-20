import ClipDockCore
import SwiftUI
@preconcurrency import Translation

/// Asks macOS to download the chosen languages' files once. `prepareTranslation()` needs a
/// session from SwiftUI's `.translationTask`, so the system's download prompt can attach to
/// this window. Only the missing languages are asked for.
struct LanguagePackCardView: View {
    var extra: [TranslationDirection] = []
    let onDismiss: @MainActor () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Download Translation Languages", systemImage: "character.bubble")
                .font(.headline)
            Text("Sputnik translates with Apple's on-device engine, so your text never leaves this Mac. It needs the \(Self.languageList(extra: extra)) language files once.")
            Text("Click Download, then confirm in the macOS prompt for each language. This window closes by itself when they're all ready.")
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
                // One download usually covers both directions of a pair. Ask for whatever is left.
                configuration = Self.configuration(for: await LanguagePacks.missingDirections(extra: extra).first)
            } catch {
                Log.translate.error("language download failed: \(String(describing: error), privacy: .public)")
                errorMessage = "The download didn't finish. Try again."
                configuration = nil
            }
        }
    }

    /// Starts with the first missing pair. If nothing is missing, the controller closes the card.
    private func start() {
        errorMessage = nil
        let extra = extra
        Task { configuration = Self.configuration(for: await LanguagePacks.missingDirections(extra: extra).first) }
    }

    /// "English, Russian and French".
    private static func languageList(extra: [TranslationDirection]) -> String {
        var languages = AppSettings.languages.all
        for direction in extra {
            for language in [direction.source, direction.target] where !languages.contains(language) { languages.append(language) }
        }
        return ListFormatter.localizedString(byJoining: languages.map(\.name))
    }

    private static func configuration(for direction: TranslationDirection?) -> TranslationSession.Configuration? {
        direction.map { .init(source: $0.sourceLanguage, target: $0.targetLanguage) }
    }
}
