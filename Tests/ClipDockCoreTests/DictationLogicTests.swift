import Foundation
import Testing
@testable import ClipDockCore

@Suite("Hold fn to talk")
struct HoldToTalkDetectorTests {
    @Test("Hold, speak, release")
    func hold() {
        var detector = HoldToTalkDetector()
        #expect(detector.handle(.fnDown(at: 0)) == [.begin])
        #expect(detector.handle(.tick(at: 0.1)).isEmpty)
        #expect(detector.handle(.tick(at: 0.31)) == [.confirm(handsFree: false)])
        #expect(detector.handle(.fnUp(at: 2)) == [.finish(.dictate)])
    }

    @Test("Released past the threshold before a tick still counts")
    func holdWithoutTick() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0))
        #expect(detector.handle(.fnUp(at: 0.5)) == [.confirm(handsFree: false), .finish(.dictate)])
    }

    @Test("A quick tap is thrown away")
    func tap() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0))
        #expect(detector.handle(.fnUp(at: 0.1)) == [.cancel])
        #expect(detector.handle(.tick(at: 0.6)).isEmpty)
        #expect(detector.handle(.fnDown(at: 2)) == [.begin])
        #expect(detector.handle(.fnUp(at: 2.1)) == [.cancel])  // too late to be a double tap
    }

    @Test("Double-tap for hands-free; fn again finishes; other keys don't stop it")
    func handsFree() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.fnUp(at: 0.1))
        #expect(detector.handle(.fnDown(at: 0.3)) == [.begin])
        #expect(detector.handle(.fnUp(at: 0.4)) == [.confirm(handsFree: true)])
        #expect(detector.isListening)
        #expect(detector.handle(.key(isEscape: false)).isEmpty)
        #expect(detector.handle(.fnDown(at: 9)) == [.finish(.dictate)])
        #expect(detector.handle(.fnUp(at: 9.1)).isEmpty)
        #expect(!detector.isListening)
    }

    @Test("Esc cancels hands-free")
    func handsFreeEscape() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.fnUp(at: 0.1))
        _ = detector.handle(.fnDown(at: 0.3))
        _ = detector.handle(.fnUp(at: 0.4))
        #expect(detector.handle(.key(isEscape: true)) == [.cancel])
    }

    @Test("Another key while holding cancels (fn shortcuts keep working)")
    func otherKeyCancels() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.tick(at: 0.4))
        #expect(detector.handle(.key(isEscape: false)) == [.cancel])
        #expect(detector.handle(.fnUp(at: 1)).isEmpty)
        #expect(detector.handle(.fnDown(at: 3)) == [.begin])
    }

    @Test("⌃ makes it a command, ⇧ a translation; ⌘ cancels")
    func modes() {
        var detector = HoldToTalkDetector()
        _ = detector.handle(.fnDown(at: 0))
        #expect(detector.handle(.modifiers([.control])) == [.modeChanged(.command)])
        _ = detector.handle(.tick(at: 0.4))
        #expect(detector.handle(.fnUp(at: 1)) == [.finish(.command)])

        _ = detector.handle(.fnDown(at: 5))
        #expect(detector.handle(.modifiers([.shift])) == [.modeChanged(.translate)])
        #expect(detector.handle(.fnUp(at: 6)) == [.confirm(handsFree: false), .finish(.translate)])

        _ = detector.handle(.fnDown(at: 10))
        #expect(detector.handle(.modifiers([.command])) == [.cancel])
    }
}

@Suite("Dictation clean-up")
struct DictationCleanupTests {
    @Test("Filler sounds go, in English and Russian")
    func fillers() {
        #expect(DictationCleanup.clean("Um, so I wanted to check.") == "So I wanted to check.")
        #expect(DictationCleanup.clean("Thanks uh.") == "Thanks.")
        #expect(DictationCleanup.clean("Эм, пришлите договор") == "Пришлите договор")
        #expect(DictationCleanup.clean("I like it") == "I like it")
    }

    @Test("Spoken layout becomes line breaks")
    func layout() {
        #expect(DictationCleanup.clean("Hi Anna new line thanks for the update") == "Hi Anna\nThanks for the update")
        #expect(DictationCleanup.clean("Dear team. New paragraph. We are ready.") == "Dear team.\n\nWe are ready.")
        #expect(DictationCleanup.clean("Привет новая строка как дела") == "Привет\nКак дела")
    }

    @Test("Spacing is tidied; numbers keep their commas")
    func spacing() {
        #expect(DictationCleanup.clean("hello ,world") == "Hello, world")
        #expect(DictationCleanup.clean("It costs 3,000 dollars  today") == "It costs 3,000 dollars today")
    }
}

@Suite("English or Russian")
struct TranscriptPickerTests {
    @Test("Picks the reading that fits the language")
    func picks() {
        let english = TranscriptPicker.pick([
            .init(language: .english, text: "So I wanted to check if we can meet on Thursday", confidence: 0.83),
            .init(language: .russian, text: "Мам san wake for Thanks", confidence: 0.4),
        ])
        #expect(english?.language == .english)
        let russian = TranscriptPicker.pick([
            .init(language: .english, text: ", , , , , ,", confidence: 0.05),
            .init(language: .russian, text: "Здравствуйте пришлите пожалуйста договор", confidence: nil),
        ])
        #expect(russian?.language == .russian)
        #expect(TranscriptPicker.pick([.init(language: .english, text: "", confidence: 0.9)]) == nil)
    }
}

@Suite("Voice commands")
struct VoiceCommandTests {
    @Test("Insert a saved item by name")
    func snippets() {
        #expect(VoiceCommand.snippetName(in: "Insert my office address.") == "office address")
        #expect(VoiceCommand.snippetName(in: "вставь адрес офиса") == "адрес офиса")
        #expect(VoiceCommand.snippetName(in: "insert") == nil)
        #expect(VoiceCommand.snippetName(in: "please insert it") == nil)
    }

    @Test("Instructions for the selection")
    func parse() {
        #expect(VoiceCommand.parse("Translate to Russian") == .translate(to: .russian))
        #expect(VoiceCommand.parse("переведи на английский") == .translate(to: .english))
        #expect(VoiceCommand.parse("Make it shorter") == .rewrite(.shorter))
        #expect(VoiceCommand.parse("proofread this please") == .rewrite(.proofread))
        #expect(VoiceCommand.parse("make it more formal") == .rewrite(.professional))
        #expect(VoiceCommand.parse("сделай официальнее") == .rewrite(.professional))
        #expect(VoiceCommand.parse("add a joke at the end") == .freeform("add a joke at the end"))
    }

    @Test("Matches the spoken name to a saved item")
    func names() {
        #expect(SavedNameMatcher.match(spoken: "office address", names: ["Home address", "Office address", "Office"]) == 1)
        #expect(SavedNameMatcher.match(spoken: "office", names: ["Office address", "Office"]) == 1)
        #expect(SavedNameMatcher.match(spoken: "адрес офиса", names: ["Адрес офиса"]) == 0)
        #expect(SavedNameMatcher.match(spoken: "bank", names: ["IBAN"]) == nil)
    }

    @Test("A polished dictation must stay close to what was said")
    func plausible() {
        #expect(RewriteStyle.isPlausibleCleanup(original: "um so we meet at four", cleaned: "So we meet at four."))
        #expect(!RewriteStyle.isPlausibleCleanup(original: "what is the capital of France", cleaned: String(repeating: "Paris is the capital. ", count: 5)))
    }
}

@Suite("Voice snippets end to end")
struct VoiceSnippetFlowTests {
    @Test("“Insert test snippet alpha.” finds the saved item")
    func flow() {
        let spoken = DictationCleanup.clean("Insert test snippet alpha.")
        let name = VoiceCommand.snippetName(in: spoken)
        #expect(name == "test snippet alpha")
        #expect(SavedNameMatcher.match(spoken: name ?? "", names: ["OpenAI key", "Test snippet alpha"]) == 1)
    }
}

@Suite("Near matches and Russian polish guard")
struct DictationRobustnessTests {
    @Test("A misheard saved-item name still matches; unrelated names don't")
    func nearMatch() {
        let names = ["OpenAI key", "Test snippet alpha", "Office address"]
        #expect(SavedNameMatcher.match(spoken: VoiceCommand.snippetName(in: "Insert tests nippid alpha.") ?? "", names: names) == 1)
        #expect(SavedNameMatcher.match(spoken: "office adress", names: names) == 2)
        #expect(SavedNameMatcher.match(spoken: "grocery list", names: names) == nil)
    }

    @Test("A Russian dictation that comes back in English is rejected")
    func scriptGuard() {
        let russian = "ну вот смотри нам нужно три вещи"
        #expect(RewriteStyle.isPlausibleCleanup(original: russian, cleaned: "Вот смотри, нам нужно три вещи."))
        #expect(!RewriteStyle.isPlausibleCleanup(original: russian, cleaned: "Look, we need three things."))
    }
}
