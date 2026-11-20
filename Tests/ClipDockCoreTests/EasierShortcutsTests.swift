import Foundation
import Testing
@testable import ClipDockCore

@Suite("Say the language first")
struct SpokenLanguageTests {
    @Test("English lead-ins pick the language and aren't typed")
    func english() {
        #expect(SpokenLanguage.split("In French, see you tomorrow at the office.")
            == .init(language: .french, rest: "See you tomorrow at the office."))
        #expect(SpokenLanguage.split("Translate to Russian: the contract is signed")
            == .init(language: .russian, rest: "The contract is signed"))
        #expect(SpokenLanguage.split("Translate into English. Bonjour à tous")
            == .init(language: .english, rest: "Bonjour à tous"))
        #expect(SpokenLanguage.split("in french see you") == .init(language: .french, rest: "See you"))
    }

    @Test("Russian lead-ins, with or without the hyphen")
    func russian() {
        #expect(SpokenLanguage.split("По-английски, увидимся завтра.") == .init(language: .english, rest: "Увидимся завтра."))
        #expect(SpokenLanguage.split("по французски увидимся завтра") == .init(language: .french, rest: "Увидимся завтра"))
        #expect(SpokenLanguage.split("На английском: спасибо за встречу") == .init(language: .english, rest: "Спасибо за встречу"))
        #expect(SpokenLanguage.split("Переведи на французский спасибо") == .init(language: .french, rest: "Спасибо"))
    }

    @Test("Ordinary sentences aren't lead-ins")
    func notLeadIns() {
        #expect(SpokenLanguage.split("See you tomorrow in French class") == nil)
        #expect(SpokenLanguage.split("In France we meet at four") == nil)
        #expect(SpokenLanguage.split("Into the office by nine") == nil)
        #expect(SpokenLanguage.split("To French customers we offer a discount") == nil)
        #expect(SpokenLanguage.split("In English we say hello") == nil)
        #expect(SpokenLanguage.split("На русском рынке всё хорошо") == nil)
        #expect(SpokenLanguage.split("Пока, увидимся на русской выставке") == nil)
    }

    @Test("Only the language said: nothing left to translate")
    func onlyLanguage() {
        #expect(SpokenLanguage.split("In French.") == .init(language: .french, rest: ""))
    }
}

@Suite("Right ⌥ as a talk key")
struct DelayedHoldKeyTests {
    @Test("A hold starts after the delay, from the press time")
    func hold() {
        var key = DelayedHoldKey()
        #expect(key.handle(.down(at: 10)) == nil)
        #expect(key.isPending)
        #expect(key.handle(.tick(at: 10.1)) == nil)
        #expect(key.handle(.tick(at: 10.21)) == .began(at: 10))
        #expect(!key.isPending)
        #expect(key.handle(.up(at: 12)) == .ended(at: 12))
    }

    @Test("Quick taps (⌥⌥) never start")
    func taps() {
        var key = DelayedHoldKey()
        _ = key.handle(.down(at: 0))
        #expect(key.handle(.up(at: 0.08)) == nil)
        _ = key.handle(.down(at: 0.2))
        #expect(key.handle(.up(at: 0.28)) == nil)
        #expect(key.handle(.tick(at: 1)) == nil)
    }

    @Test("⌥ + a letter or ⌥-click blocks it until released")
    func typing() {
        var key = DelayedHoldKey()
        _ = key.handle(.down(at: 0))
        _ = key.handle(.otherInput)
        #expect(key.handle(.tick(at: 1)) == nil)
        #expect(key.handle(.up(at: 2)) == nil)
        _ = key.handle(.down(at: 3))
        #expect(key.handle(.tick(at: 3.3)) == .began(at: 3))
    }

    @Test("A talk key with hands-free off: two taps don't start hands-free")
    func noHandsFree() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0, allowsHandsFree: false))
        _ = detector.handle(.fnUp(at: 0.1))
        _ = detector.handle(.fnDown(at: 0.3, allowsHandsFree: false))
        #expect(detector.handle(.fnUp(at: 0.4)) == [.cancel])
        #expect(!detector.isListening)
    }

    @Test("Hands-free keeps listening through ⌘ and ⌥ (⌘Tab, ⌘C)")
    func handsFreeIgnoresCommand() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.fnUp(at: 0.1))
        _ = detector.handle(.fnDown(at: 0.3))
        _ = detector.handle(.fnUp(at: 0.4))
        #expect(detector.handle(.modifiers([.command])).isEmpty)
        #expect(detector.handle(.modifiers([.option])).isEmpty)
        #expect(detector.isListening)
        #expect(detector.handle(.fnDown(at: 5)) == [.finish(.dictate)])
    }
}

@Suite("Proofread in place")
struct ProofreadOutcomeTests {
    @Test("A correction keeps the selection's surrounding whitespace")
    func corrected() {
        #expect(ProofreadOutcome.of(original: "i has a apple\n", corrected: "I have an apple.")
            == .corrected("I have an apple.\n"))
        #expect(ProofreadOutcome.of(original: "  teh meeting", corrected: " The meeting ") == .corrected("  The meeting"))
        #expect(ProofreadOutcome.of(original: "ok", corrected: "Okay.") == .corrected("Okay."))
    }

    @Test("Nothing to fix")
    func unchanged() {
        #expect(ProofreadOutcome.of(original: "All good here.\n", corrected: "All good here.") == .unchanged)
    }

    @Test("Rewrites, answers and translations are refused")
    func implausible() {
        let original = "can you send me the contract by friday"
        #expect(ProofreadOutcome.of(original: original, corrected: "") == .implausible)
        #expect(ProofreadOutcome.of(original: original, corrected: "Можете прислать мне договор до пятницы?") == .implausible)
        #expect(ProofreadOutcome.of(original: original, corrected: "Of course! Here is a short guide to sending contracts: first, open the file, then attach it to an email and press send.") == .implausible)
        #expect(ProofreadOutcome.of(original: "   ", corrected: "Hi") == .implausible)
    }
}

@Suite("Shortcuts guide")
struct ShortcutGuideTests {
    private func options(proofread: TapModifier? = .shift, dictation: Bool = true, sayLanguage: Bool = true) -> ShortcutGuide.Options {
        .init(popupTap: .option, translateTap: .control, proofreadTap: proofread, dictation: dictation,
              rightOption: true, sayLanguage: sayLanguage, voiceCommands: true, englishTarget: .russian)
    }

    @Test("Shows the keys as set")
    func keys() {
        let sections = ShortcutGuide.sections(options())
        #expect(sections.map(\.title) == ["Talk", "Selected text, in any app", "Clipboard"])
        let selection = sections[1].rows
        #expect(selection.map(\.keys) == [["⌃", "⌃"], ["⇧", "⇧"]])
        #expect(sections[0].rows[0].detail?.contains("right ⌥") == true)
        #expect(sections[0].rows.contains { $0.title == "Talk in English, type in Russian" })
    }

    @Test("Switched-off features aren't listed")
    func off() {
        let sections = ShortcutGuide.sections(options(proofread: nil, dictation: false))
        #expect(!sections.contains { $0.title == "Talk" })
        #expect(sections[0].rows.map(\.title) == ["Translate"])
        #expect(!ShortcutGuide.sections(options(sayLanguage: false))[0].rows.contains { $0.title == "Say the language first" })
    }
}
