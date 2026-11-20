import Testing
@testable import SputnikCore

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

    @Test("Space toggles the multi-select mark; ⇧Space is Quick Look")
    func space() {
        #expect(command(0x31) == .toggleMark)
        #expect(command(0x31, .shift) == .peek)
        #expect(command(0x31, .option) == nil)
    }

    @Test("Typing and other combinations go to the search field")
    func passThrough() {
        #expect(command(0x00) == nil)              // "a" (or "ф" in Russian)
        #expect(command(0x33) == nil)              // ⌫ edits the query
        #expect(command(0x12) == nil)              // "1" without ⌘
        #expect(command(0x12, [.command, .shift]) == nil)
        #expect(command(0x08, .option) == nil)
    }

    @Test("Actions menu keys: ⌘K, ⌥↩, ⌘O, ⌘E, ⌘N, and ⇥ for the tabs")
    func actionKeys() {
        #expect(command(0x28, .command) == .showActions)
        #expect(command(0x24, .option) == .pastePlain)
        #expect(command(0x4C, .option) == .pastePlain)
        #expect(command(0x1F, .command) == .openSelected)
        #expect(command(0x0E, .command) == .editSelected)
        #expect(command(0x2D, .command) == .newSaved)
        #expect(command(0x30) == .switchScope)
        #expect(command(0x30, .shift) == .previousScope)
        #expect(command(0x25, .command) == .saveAsSecret)
        #expect(command(0x28) == nil)  // plain "k" types
        #expect(command(0x25) == nil)  // plain "l" types
    }
}

@Suite("Editor keys")
struct EditorKeymapTests {
    func command(_ keyCode: UInt16, _ modifiers: PopupKeymap.Modifiers = []) -> EditorCommand? {
        EditorKeymap.command(keyCode: keyCode, modifiers: modifiers)
    }

    @Test("Esc cancels; ⌘S saves; ⌘↩ is the main action; ⌘L toggles Secret")
    func commands() {
        #expect(command(0x35) == .cancel)
        #expect(command(0x01, .command) == .save)
        #expect(command(0x24, .command) == .primary)
        #expect(command(0x25, .command) == .toggleSecret)
    }

    @Test("Text editing shortcuts work without an Edit menu")
    func editing() {
        #expect(command(0x00, .command) == .selectAll)
        #expect(command(0x07, .command) == .cut)
        #expect(command(0x08, .command) == .copy)
        #expect(command(0x09, .command) == .paste)
        #expect(command(0x06, .command) == .undo)
        #expect(command(0x06, [.command, .shift]) == .redo)
    }

    @Test("Return, Space, arrows, and Tab go to the text fields")
    func passThrough() {
        #expect(command(0x24) == nil)
        #expect(command(0x31) == nil)
        #expect(command(0x7E) == nil)
        #expect(command(0x30) == nil)
        #expect(command(0x2D, .command) == nil)  // ⌘N does nothing while editing
    }
}
