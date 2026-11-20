import Testing
@testable import SputnikCore

@Suite("Language detection")
struct LanguageDetectorTests {
    @Test("Russian text goes RU → EN", arguments: [
        "Привет, как дела?",
        "Встреча в 10:00 в офисе.",
        "ОТЧЁТ ЗА КВАРТАЛ",
        "ё",
    ])
    func russian(text: String) {
        #expect(LanguageDetector.direction(for: text) == .russianToEnglish)
    }

    @Test("French text goes FR → EN", arguments: [
        "Bonjour",
        "Merci beaucoup",
        "D'accord",
        "Salut, ça va ?",
        "Je vous remercie pour votre message.",
        "La réunion est à 10h.",
        "Pouvez-vous m'envoyer le contrat ?",
        "Le client a validé le devis",
        "Bonne journée",
        "facture",
    ])
    func french(text: String) {
        #expect(LanguageDetector.direction(for: text) == .frenchToEnglish)
    }

    @Test("English and unplaceable text goes EN → RU by default", arguments: [
        "Good morning, the meeting is at 10.",
        "OK",
        "Thanks",
        "1234 5678",
        "",
        "   \n  ",
        "Let's meet at the café tomorrow",
        "Call José at 5",
        "Merci, see you tomorrow",
        "menu",
    ])
    func english(text: String) {
        #expect(LanguageDetector.direction(for: text) == .englishToRussian)
    }

    @Test("English goes into French when that's the setting; foreign text still goes into English")
    func englishTarget() {
        #expect(LanguageDetector.direction(for: "The client approved the quote", englishTarget: .french) == .englishToFrench)
        #expect(LanguageDetector.direction(for: "Le client a validé le devis", englishTarget: .french) == .frenchToEnglish)
        #expect(LanguageDetector.direction(for: "Привет, как дела?", englishTarget: .french) == .russianToEnglish)
        // English → English isn't a translation; it falls back to Russian.
        #expect(LanguageDetector.direction(for: "Hello there", englishTarget: .english) == .englishToRussian)
    }

    @Test("More than 30% Cyrillic letters counts as Russian")
    func threshold() {
        // 6 Cyrillic letters out of 15 (40%).
        #expect(LanguageDetector.language(of: "Meeting в офисе") == .russian)
        // Product names in a Russian sentence.
        #expect(LanguageDetector.language(of: "Купить iPhone 15 Pro недорого") == .russian)
    }

    @Test("A few Russian or French words inside English stay English")
    func mostlyEnglish() {
        #expect(LanguageDetector.language(of: "The Russian word привет means hello in English") == .english)
        #expect(LanguageDetector.language(of: "The French say bonjour when they arrive at the office") == .english)
    }

    @Test("Cyrillic share counts letters only")
    func share() {
        #expect(LanguageDetector.cyrillicShare(of: "абв abc") == 0.5)
        #expect(LanguageDetector.cyrillicShare(of: "123 !?") == nil)
        #expect(LanguageDetector.cyrillicShare(of: "Дом 2") == 1.0)
    }

    @Test("Directions are labelled for the card and logs")
    func labels() {
        #expect(TranslationDirection.frenchToEnglish.label == "FR → EN")
        #expect(TranslationDirection.englishToRussian.id == "en-ru")
        #expect(Set(LanguageSetup.omar.directions).count == 4)
    }
}
