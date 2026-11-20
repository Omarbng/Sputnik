import Foundation

/// Tidies what Apple's model returns: it sometimes opens with "Sure! Here's the edited text:"
/// or wraps the answer in quotes or a code fence, despite being told not to.
public enum RewriteOutput {
    /// A first line like these is the model talking, not the text.
    static let preamblePattern = #"^\s*(sure|certainly|of course|okay|ok|here(’|')?s|here is|below is|the (edited|cleaned|corrected|rewritten) text|вот|конечно)\b[^\n]{0,80}:\s*$"#

    /// `original` is the text that was edited: a first line that's really Omar's own words
    /// ("Here's the plan:") stays.
    public static func clean(_ raw: String, original: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = result.components(separatedBy: "\n")
        if lines.count > 1, lines[0].range(of: preamblePattern, options: [.regularExpression, .caseInsensitive]) != nil,
           !letters(of: original).contains(letters(of: lines[0])) {
            result = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if result.hasPrefix("```"), result.hasSuffix("```"), result.count > 6 {
            result = String(result.dropFirst(3).dropLast(3))
            if let newline = result.firstIndex(of: "\n"), !result[..<newline].contains(" ") {
                result = String(result[result.index(after: newline)...])  // a language tag
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (open, close) in [("\"", "\""), ("“", "”"), ("«", "»")] where result.hasPrefix(open) && result.hasSuffix(close) && result.count > 2 {
            let inner = result.dropFirst().dropLast()
            if !inner.contains(open), !inner.contains(close) { result = String(inner) }
        }
        return result
    }

    private static func letters(of text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
