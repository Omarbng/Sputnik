/// Splits text into lines for translation and puts it back together exactly. Line breaks
/// (including `\r\n`), blank lines, indentation, and leading and trailing whitespace are kept.
/// Only each line's inner content is translated.
public struct TextLayout: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var leading: String
        public var content: String
        public var trailing: String
        /// The line break after this line, or "" for the last line.
        public var lineBreak: String
    }

    public private(set) var lines: [Line]

    public init(_ text: String) {
        var lines: [Line] = []
        var buffer = ""
        for character in text {
            if character.isNewline {
                lines.append(Self.line(buffer, lineBreak: String(character)))
                buffer = ""
            } else {
                buffer.append(character)
            }
        }
        lines.append(Self.line(buffer, lineBreak: ""))
        self.lines = lines
    }

    /// What to send to the translator, in order. Blank lines are left out.
    public var translatableParts: [String] {
        lines.map(\.content).filter { !$0.isEmpty }
    }

    /// The text with `translations` in place of `translatableParts`, in the same order.
    /// A missing translation keeps the original line.
    public func rebuilt(with translations: [String]) -> String {
        var next = translations.makeIterator()
        return lines.map { line in
            let content = line.content.isEmpty ? "" : (next.next() ?? line.content)
            return line.leading + content + line.trailing + line.lineBreak
        }.joined()
    }

    private static func line(_ text: String, lineBreak: String) -> Line {
        let leading = text.prefix { $0.isWhitespace }
        let rest = text.dropFirst(leading.count)
        let trailingCount = rest.reversed().prefix { $0.isWhitespace }.count
        return Line(
            leading: String(leading),
            content: String(rest.dropLast(trailingCount)),
            trailing: String(rest.suffix(trailingCount)),
            lineBreak: lineBreak
        )
    }
}
