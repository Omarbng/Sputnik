import Testing
@testable import ClipDockCore

@Suite("Popup keys")
struct PopupKeymapTests {
    func command(_ keyCode: UInt16, _ modifiers: PopupKeymap.Modifiers = []) -> PopupCommand? {
        PopupKeymap.command(keyCode: keyCode, modifiers: modifiers)
    }

    @Test("Plain keys: Esc, Return, Enter, arrows")
    func plainKeys() {
        #expect(command(0x35) == .close)
        #expect(command(0x24) == .pasteSelected)
        #expect(command(0x4C) == .pasteSelected)
        #expect(command(0x7E) == .moveUp)
        #expect(command(0x7D) == .moveDown)
    }

    @Test("⌘1–⌘9 paste the Nth item, by key code (works with any layout)")
    func numberKeys() {
        let codes: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
        for (index, code) in codes.enumerated() {
            #expect(command(code, .command) == .pasteNumber(index + 1))
        }
    }

    @Test("⌘C copies, ⌘⌫ deletes, ⌘A/⌘X/⌘V edit the search text")
    func commandKeys() {
        #expect(command(0x08, .command) == .copySelected)
        #expect(command(0x33, .command) == .deleteSelected)
        #expect(command(0x11, .command) == .translateSelected)
        #expect(command(0x24, .command) == .pasteMarked)
        #expect(command(0x4C, .command) == .pasteMarked)
        #expect(command(0x23, .command) == .togglePin)
        #expect(command(0x2B, .command) == .openSettings)
        #expect(command(0x00, .command) == .selectAllText)
        #expect(command(0x07, .command) == .cutText)
        #expect(command(0x09, .command) == .pasteText)
    }

    @Test("Space toggles the multi-select mark")
    func space() {
        #expect(command(0x31) == .toggleMark)
        #expect(command(0x31, .shift) == nil)
    }

    @Test("Typing and other combinations go to the search field")
    func passThrough() {
        #expect(command(0x00) == nil)              // "a" (or "ф" in Russian)
        #expect(command(0x33) == nil)              // ⌫ edits the query
        #expect(command(0x12) == nil)              // "1" without ⌘
        #expect(command(0x12, [.command, .shift]) == nil)
        #expect(command(0x08, .option) == nil)
    }
}
