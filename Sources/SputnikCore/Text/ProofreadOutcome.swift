import Foundation

/// What to do with Apple Intelligence's proofread of a selection (double-tap ⇧).
public enum ProofreadOutcome: Equatable, Sendable {
    /// Nothing to fix: leave the text alone.
    case unchanged
    /// Not a correction any more (rewritten, answered, or in another alphabet): leave it alone.
    case implausible
    /// Paste this over the selection. It keeps the selection's leading and trailing whitespace,
    /// so a selected line keeps its line break.
    case corrected(String)

    public static func of(original: String, corrected: String) -> ProofreadOutcome {
        let core = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let fixed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty, !fixed.isEmpty else { return .implausible }
        guard fixed != core else { return .unchanged }
        // A proofread changes a few characters, not the length (short texts get some slack:
        // "ok" → "Okay.").
        let difference = abs(fixed.count - core.count)
        guard difference <= max(12, core.count * 3 / 10) else { return .implausible }
        guard RewriteStyle.sameAlphabet(core, fixed) else { return .implausible }
        let leading = original.prefix { $0.isWhitespace || $0.isNewline }
        let trailing = String(original.reversed().prefix { $0.isWhitespace || $0.isNewline }.reversed())
        return .corrected(leading + fixed + trailing)
    }
}
