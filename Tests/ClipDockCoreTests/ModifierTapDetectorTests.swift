import Testing
@testable import ClipDockCore

@Suite("Double-tap shortcuts")
struct ModifierTapDetectorTests {
    /// Runs a script of inputs and returns every modifier that fired.
    func run(_ inputs: [ModifierTapDetector.Input]) -> [TapModifier] {
        var detector = ModifierTapDetector()
        return inputs.compactMap { detector.handle($0) }
    }

    func down(_ m: TapModifier, _ t: Double) -> ModifierTapDetector.Input { .modifiers([m], at: t) }
    func up(_ t: Double) -> ModifierTapDetector.Input { .modifiers([], at: t) }

    @Test("Two quick taps of ⌥ fire once, on the second release")
    func doubleTap() {
        #expect(run([down(.option, 0), up(0.08), down(.option, 0.2), up(0.28)]) == [.option])
    }

    @Test("It works for ⌃ too, and ⌥ then ⌃ doesn't count")
    func perModifier() {
        #expect(run([down(.control, 0), up(0.1), down(.control, 0.25), up(0.33)]) == [.control])
        #expect(run([down(.option, 0), up(0.1), down(.control, 0.25), up(0.33)]).isEmpty)
    }

    @Test("A long pause between taps doesn't count, but the second tap can start a new pair")
    func slowGap() {
        #expect(run([down(.option, 0), up(0.1), down(.option, 0.9), up(1.0)]).isEmpty)
        #expect(run([down(.option, 0), up(0.1), down(.option, 0.9), up(1.0), down(.option, 1.2), up(1.28)]) == [.option])
    }

    @Test("Holding the key too long isn't a tap")
    func longPress() {
        #expect(run([down(.option, 0), up(0.1), down(.option, 0.2), up(1.2)]).isEmpty)
    }

    @Test("A key press between taps cancels it (typing with ⌥, like ⌥E for an accent)")
    func keyBetween() {
        #expect(run([down(.option, 0), up(0.1), down(.option, 0.2), .otherInput, up(0.3)]).isEmpty)
        #expect(run([down(.option, 0), .otherInput, up(0.1), down(.option, 0.2), up(0.3)]).isEmpty)
    }

    @Test("Combos like ⌥⌘T never count, even when keys are released one by one")
    func combos() {
        let combo: [ModifierTapDetector.Input] = [
            down(.option, 0), .modifiers([.option, .command], at: 0.05), .otherInput,
            down(.option, 0.15), up(0.2),          // ⌘ released first, then ⌥
            down(.option, 0.3), up(0.36),          // one real tap afterwards
        ]
        #expect(run(combo).isEmpty)
    }

    @Test("A third tap doesn't fire again; four taps fire twice")
    func repeatedTaps() {
        let taps = (0..<4).flatMap { i in [down(.option, Double(i) * 0.2), up(Double(i) * 0.2 + 0.08)] }
        #expect(run(Array(taps.prefix(6))) == [.option])
        #expect(run(taps) == [.option, .option])
    }

    @Test("A click while holding the key cancels it")
    func clickCancels() {
        #expect(run([down(.command, 0), up(0.1), down(.command, 0.2), .otherInput, up(0.25)]).isEmpty)
    }
}
