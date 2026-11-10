#if DEBUG
import ClipDockCore

/// Debug builds only, enabled with `CLIPDOCK_FAKE_TRANSLATOR=1`. It tags each line with its
/// target language (`[ru] Hello`), so replacement, clipboard restore, and line breaks can be
/// tested without the language files.
struct FakeTranslator: Translator {
    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        let layout = TextLayout(text)
        return layout.rebuilt(with: layout.translatableParts.map { "[\(direction.targetCode)] \($0)" })
    }
}
#endif
