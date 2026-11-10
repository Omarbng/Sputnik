import Testing
@testable import ClipDockCore

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

    @Test("English and other text goes EN → RU", arguments: [
        "Good morning, the meeting is at 10.",
        "OK",
        "1234 5678",
        "",
        "   \n  ",
        "Grüß Gott, wie geht's?",
    ])
    func notRussian(text: String) {
        #expect(LanguageDetector.direction(for: text) == .englishToRussian)
    }

    @Test("More than 30% Cyrillic letters counts as Russian")
    func threshold() {
        // 6 Cyrillic letters out of 15 (40%).
        #expect(LanguageDetector.isRussian("Meeting в офисе"))
        // Product names in a Russian sentence.
        #expect(LanguageDetector.isRussian("Купить iPhone 15 Pro недорого"))
    }

    @Test("A few Russian words inside English stay English")
    func mostlyEnglish() {
        #expect(!LanguageDetector.isRussian("The Russian word привет means hello in English"))
    }

    @Test("Cyrillic share counts letters only")
    func share() {
        #expect(LanguageDetector.cyrillicShare(of: "абв abc") == 0.5)
        #expect(LanguageDetector.cyrillicShare(of: "123 !?") == nil)
        #expect(LanguageDetector.cyrillicShare(of: "Дом 2") == 1.0)
    }
}
