import Foundation
import Testing
@testable import SputnikCore

@Suite("Anyone's languages")
struct LanguageSetupTests {
    @Test("Omar's ClipDock settings carry over")
    func migration() {
        #expect(LanguageSetup.migrated(englishTarget: nil, dictation: nil) == .omar)
        let french = LanguageSetup.migrated(englishTarget: "fr", dictation: "english")
        #expect(french.main == .english && french.others == [.russian, .french])
        #expect(french.target == .french && french.spoken == [.english])
        #expect(LanguageSetup.migrated(englishTarget: "de", dictation: "russian").target == .russian)
    }

    @Test("A new Mac starts from its own language")
    func suggested() {
        let german = LanguageSetup.suggested(preferredLanguages: ["de-DE", "en-US"])
        #expect(german.main == .german && german.others == [.english] && german.target == .english && german.spoken == [.german])
        #expect(LanguageSetup.suggested(preferredLanguages: ["en-GB"]).others.isEmpty)
        #expect(LanguageSetup.suggested(preferredLanguages: ["zh-Hant-TW"]).main == .chineseTraditional)
        #expect(LanguageSetup.suggested(preferredLanguages: ["sw-KE"]).main == .english)  // Swahili: no Apple translation
    }

    @Test("Choices stay consistent")
    func normalized() {
        var setup = LanguageSetup(main: .english, others: [.english, .german, .german, .spanish], target: .french, spoken: [.english, .japanese, .german, .spanish])
        #expect(setup.others == [.german, .spanish])
        #expect(setup.target == .german)  // French isn't chosen
        #expect(setup.spoken == [.english, .german, .spanish])  // Japanese isn't chosen
        setup.setMain(.german)
        #expect(setup.main == .german && setup.others == [.english, .spanish])
        setup.setOthers([])
        #expect(setup.target == nil && setup.spoken == [.german])
        #expect(LanguageSetup.omar.directions.count == 4)
    }

    @Test("Saved and loaded")
    func codable() throws {
        let data = try JSONEncoder().encode(LanguageSetup.omar)
        #expect(try JSONDecoder().decode(LanguageSetup.self, from: data) == .omar)
    }

    @Test("The catalog matches Apple's on-device translation languages")
    func catalog() {
        #expect(TranslationLanguage.catalog.count == 20)
        #expect(TranslationLanguage.catalog.first?.name == "Arabic")
        #expect(TranslationLanguage.german.nativeName == "Deutsch")
        #expect(TranslationLanguage.ukrainian.script == .cyrillic)
    }
}

@Suite("Detecting any of someone's languages")
struct GeneralLanguageDetectorTests {
    private let german = LanguageSetup(main: .german, others: [.english, .spanish], target: .english, spoken: [])

    @Test("A German speaker: other languages into German, German into English")
    func germanMain() {
        #expect(LanguageDetector.direction(for: "Can you send me the contract by Friday?", setup: german, target: .english)
            == TranslationDirection(.english, to: .german))
        #expect(LanguageDetector.direction(for: "¿Puedes enviarme el contrato antes del viernes?", setup: german, target: .english)
            == TranslationDirection(.spanish, to: .german))
        #expect(LanguageDetector.direction(for: "Kannst du mir den Vertrag bis Freitag schicken?", setup: german, target: .english)
            == TranslationDirection(.german, to: .english))
    }

    @Test("No other language: nothing to translate the main one into")
    func noTarget() {
        let alone = LanguageSetup(main: .english, others: [], target: nil, spoken: [])
        #expect(LanguageDetector.direction(for: "Hello there, how are you?", setup: alone, target: nil) == nil)
    }

    @Test("Scripts decide when they can")
    func scripts() {
        let all = TranslationLanguage.catalog
        #expect(LanguageDetector.language(of: "こんにちは、元気ですか", among: all, main: .english) == .japanese)
        #expect(LanguageDetector.language(of: "안녕하세요 잘 지내세요", among: all, main: .english) == TranslationLanguage(rawValue: "ko"))
        #expect(LanguageDetector.language(of: "مرحبا كيف حالك", among: all, main: .english) == TranslationLanguage(rawValue: "ar"))
        #expect(LanguageDetector.language(of: "Привет, как дела? Встречаемся завтра в офисе.", among: [.english, .russian], main: .english) == .russian)
        #expect(LanguageDetector.language(of: "Привіт, як справи? Зустрінемося завтра в офісі.", among: [.english, .russian, .ukrainian], main: .english) == .ukrainian)
    }

    @Test("Same-alphabet guesses below 60% stay in the main language")
    func confidence() {
        #expect(LanguageDetector.language(of: "menu", among: [.english, .french], main: .english) == .english)
        #expect(LanguageDetector.language(of: "12:30", among: [.german, .english], main: .german) == .german)
    }
}

@Suite("Voice in any language")
struct GeneralVoiceTests {
    @Test("Any language can be named in a command")
    func commands() {
        #expect(VoiceCommand.parse("Translate to Spanish") == .translate(to: .spanish))
        #expect(VoiceCommand.parse("translate this into German please") == .translate(to: .german))
        #expect(VoiceCommand.parse("переведи на немецкий") == .translate(to: .german))
        #expect(VoiceCommand.parse("translate to traditional Chinese") == .translate(to: .chineseTraditional))
        #expect(VoiceCommand.parse("Translate to Russian") == .translate(to: .russian))
    }

    @Test("Lead-ins for any language")
    func leadIns() {
        #expect(SpokenLanguage.split("In German, see you tomorrow.") == .init(language: .german, rest: "See you tomorrow."))
        #expect(SpokenLanguage.split("По-испански: увидимся завтра") == .init(language: .spanish, rest: "Увидимся завтра"))
        #expect(SpokenLanguage.split("In Japanese, thank you very much") == .init(language: .japanese, rest: "Thank you very much"))
    }

    @Test("Two Latin-alphabet recognisers: the text's language decides")
    func picker() {
        let english = TranscriptCandidate(language: .english, text: "Can you send me the contract by Friday", confidence: 0.8)
        let germanJunk = TranscriptCandidate(language: .german, text: "Kenn ju sent mi se kontrakt bei Freitag", confidence: 0.8)
        #expect(TranscriptPicker.pick([english, germanJunk])?.language == .english)
        let german = TranscriptCandidate(language: .german, text: "Kannst du mir den Vertrag bis Freitag schicken", confidence: 0.8)
        let englishJunk = TranscriptCandidate(language: .english, text: "Can store me then for track bees fry tack shake hen", confidence: 0.45)
        #expect(TranscriptPicker.pick([englishJunk, german])?.language == .german)
    }

    @Test("Polish prompts stay in the dictated language; alphabets are checked")
    func polish() {
        #expect(RewriteStyle.dictationPrompt(for: "hola", language: .spanish).contains("must be in Spanish"))
        #expect(RewriteStyle.dictationPrompt(for: "hi", language: .english) == RewriteStyle.dictation.prompt(for: "hi"))
        #expect(RewriteStyle.sameAlphabet("ありがとうございます", "ありがとうございます。"))
        #expect(!RewriteStyle.sameAlphabet("ありがとうございます", "Thank you very much."))
    }
}
