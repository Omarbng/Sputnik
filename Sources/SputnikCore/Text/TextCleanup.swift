/// The "clean up" actions in the actions menu.
public enum TextCleanup {
    public static func uppercased(_ text: String) -> String { text.uppercased() }

    public static func lowercased(_ text: String) -> String { text.lowercased() }

    /// Joins broken lines and squeezes repeated spaces, so text copied from a PDF or an email
    /// becomes clean paragraphs. Blank lines still separate paragraphs. The ends are trimmed.
    public static func tidied(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let paragraphs = lines.split { $0.allSatisfy(\.isWhitespace) }
        return paragraphs
            .map { $0.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
