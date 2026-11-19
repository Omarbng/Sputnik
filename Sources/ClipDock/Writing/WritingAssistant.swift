import ClipDockCore
import Foundation
import FoundationModels

/// Apple Intelligence's on-device model, for the writing actions (Proofread, Make Professional,
/// Shorter, Summarize), voice commands on a selection, and polishing dictation. Runs on this
/// Mac; nothing is sent anywhere. Apple supports English and French; Russian is best effort.
@MainActor
final class WritingAssistant {
    struct Unavailable: Error {
        let message: String
    }

    /// Edits keep close to the text, so sampling stays near-deterministic.
    private static let options = GenerationOptions(temperature: 0.2)
    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    private var warmSession: LanguageModelSession?

    /// True when Apple Intelligence is on and its model is ready.
    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    /// Why it can't run, in Settings' words; nil when it can.
    var unavailableReason: String? {
        switch model.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings"
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading"
        case .unavailable(.deviceNotEligible): "This Mac doesn't support Apple Intelligence"
        case .unavailable: "Apple Intelligence isn't available"
        }
    }

    /// Loads the model ahead of a request (the first one otherwise takes a few seconds).
    func prewarm() {
        guard isAvailable, warmSession == nil else { return }
        let session = LanguageModelSession(model: model, instructions: RewriteStyle.instructions)
        session.prewarm()
        warmSession = session
    }

    func rewrite(_ text: String, style: RewriteStyle) async throws -> String {
        try await respond(to: style.prompt(for: text), chars: text.count, label: style.rawValue)
    }

    /// A spoken instruction ("make it sound more confident") applied to a selection.
    func apply(instruction: String, to text: String) async throws -> String {
        try await respond(to: RewriteStyle.prompt(instruction: instruction, text: text), chars: text.count, label: "instruction")
    }

    private func respond(to prompt: String, chars: Int, label: String) async throws -> String {
        guard isAvailable else { throw Unavailable(message: unavailableReason ?? "Apple Intelligence isn't available") }
        // Sessions keep a transcript, so each request gets a fresh one (the warm one first).
        let session = warmSession ?? LanguageModelSession(model: model, instructions: RewriteStyle.instructions)
        warmSession = nil
        let started = ContinuousClock.now
        do {
            let response = try await session.respond(to: prompt, options: Self.options)
            let output = Self.unwrap(response.content)
            Log.writing.notice("""
                done style=\(label, privacy: .public) chars=\(chars, privacy: .public)->\(output.count, privacy: .public) \
                ms=\(Self.milliseconds(since: started), privacy: .public)
                """)
            return output
        } catch let error as LanguageModelSession.GenerationError {
            Log.writing.error("failed style=\(label, privacy: .public) reason=\(Self.reason(error), privacy: .public)")
            throw Unavailable(message: Self.message(for: error))
        }
    }

    /// The model sometimes wraps its answer in quotes or a code fence.
    static func unwrap(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```"), result.hasSuffix("```"), result.count > 6 {
            result = String(result.dropFirst(3).dropLast(3))
            if let newline = result.firstIndex(of: "\n"), !result[..<newline].contains(" ") {
                result = String(result[result.index(after: newline)...])  // drop a language tag
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("“", "”"), ("«", "»")] where result.hasPrefix(open) && result.hasSuffix(close) && result.count > 2 {
            let inner = result.dropFirst().dropLast()
            if !inner.contains(open), !inner.contains(close) { result = String(inner) }
        }
        return result
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .unsupportedLanguageOrLocale: "Apple Intelligence doesn't support this language"
        case .exceededContextWindowSize: "That text is too long for Apple Intelligence"
        case .guardrailViolation, .refusal: "Apple Intelligence declined this text"
        case .assetsUnavailable: "Apple Intelligence is still downloading"
        default: "Apple Intelligence couldn't do it"
        }
    }

    private static func reason(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .unsupportedLanguageOrLocale: "language"
        case .exceededContextWindowSize: "tooLong"
        case .guardrailViolation: "guardrail"
        case .refusal: "refusal"
        case .assetsUnavailable: "assets"
        case .rateLimited: "rateLimited"
        case .concurrentRequests: "busy"
        default: "other"
        }
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
