import SputnikCore
import Foundation
@preconcurrency import Translation

extension TranslationDirection {
    var sourceLanguage: Locale.Language { Locale.Language(identifier: sourceCode) }
    var targetLanguage: Locale.Language { Locale.Language(identifier: targetCode) }
}

/// Apple's on-device engine. Sessions are created directly with
/// `TranslationSession(installedSource:target:)`, which needs no UI (macOS 26.0+ in SDK 26.2).
/// One warm session is kept per direction. Text is split by line and sent as one batch, so
/// line breaks and surrounding whitespace survive.
actor AppleTranslator: Translator {
    private var sessions: [TranslationDirection: TranslationSession] = [:]

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        let layout = TextLayout(text)
        let parts = layout.translatableParts
        guard !parts.isEmpty else { return text }

        let requests = parts.enumerated().map { index, part in
            TranslationSession.Request(sourceText: part, clientIdentifier: String(index))
        }
        let responses: [TranslationSession.Response]
        do {
            responses = try await session(for: direction).translations(from: requests)
        } catch {
            // A session made before the languages were installed stays broken; start fresh next time.
            sessions[direction] = nil
            throw error
        }

        var translated = parts
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id), translated.indices.contains(index) {
                translated[index] = response.targetText
            }
        }
        return layout.rebuilt(with: translated)
    }

    private func session(for direction: TranslationDirection) -> TranslationSession {
        if let session = sessions[direction] { return session }
        let session = TranslationSession(installedSource: direction.sourceLanguage, target: direction.targetLanguage)
        sessions[direction] = session
        return session
    }
}
