import Testing
@testable import SputnikCore

@Suite("Paragraph splitting and rejoining")
struct TextLayoutTests {
    /// Stand-in translator: marks each part so the layout around it is easy to check.
    func fakeTranslate(_ text: String) -> String {
        let layout = TextLayout(text)
        return layout.rebuilt(with: layout.translatableParts.map { "<\($0)>" })
    }

    @Test("Rebuilding with the original parts gives back the exact text", arguments: [
        "Hello",
        "",
        "One\nTwo",
        "One\n\nTwo\n",
        "  indented\n\ttabbed  \n",
        "\n\n  Leading and trailing  \n\n",
        "Windows\r\nline\r\nbreaks\r\n",
        "Mixed\r\n\nbreaks\rhere",
        "Привет\n\nмир",
        "   ",
    ])
    func roundTrip(text: String) {
        let layout = TextLayout(text)
        #expect(layout.rebuilt(with: layout.translatableParts) == text)
    }

    @Test("Only line contents are translated; whitespace and breaks stay")
    func keepsLayout() {
        #expect(fakeTranslate("  Hello  \n\nWorld\n") == "  <Hello>  \n\n<World>\n")
        #expect(fakeTranslate("\tA\r\n\r\n  B") == "\t<A>\r\n\r\n  <B>")
    }

    @Test("Blank lines aren't sent to the translator")
    func blankLinesSkipped() {
        #expect(TextLayout("A\n\n   \nB").translatableParts == ["A", "B"])
        #expect(TextLayout("\n \n").translatableParts.isEmpty)
    }

    @Test("A short translation list keeps the remaining original lines")
    func missingTranslations() {
        #expect(TextLayout("A\nB\nC").rebuilt(with: ["x"]) == "x\nB\nC")
    }

    @Test("Multi-paragraph text keeps its paragraph count")
    func paragraphs() {
        let text = "First paragraph.\n\nSecond paragraph, longer.\n\nThird."
        let translated = fakeTranslate(text)
        #expect(translated.components(separatedBy: "\n\n").count == 3)
        #expect(translated == "<First paragraph.>\n\n<Second paragraph, longer.>\n\n<Third.>")
    }
}
