/// Names a secret Omar didn't name, so saving one takes a single key press. Only the label is
/// kept; nothing of the value goes into the name.
public enum SecretNamer {
    /// Well-known key prefixes, most specific first.
    static let prefixes: [(prefix: String, name: String)] = [
        ("sk-ant-", "Anthropic key"),
        ("sk-proj-", "OpenAI key"),
        ("sk-", "OpenAI key"),
        ("sk_live_", "Stripe key"), ("rk_live_", "Stripe key"), ("sk_test_", "Stripe test key"),
        ("github_pat_", "GitHub token"), ("ghp_", "GitHub token"), ("gho_", "GitHub token"),
        ("glpat-", "GitLab token"),
        ("xoxb-", "Slack token"), ("xoxp-", "Slack token"),
        ("AKIA", "AWS key"), ("ASIA", "AWS key"),
        ("AIza", "Google API key"),
        ("hf_", "Hugging Face token"),
        ("eyJ", "Token"),
    ]

    /// `OPENAI_API_KEY=…` is named `OPENAI_API_KEY`; a key with a known prefix gets its kind
    /// ("OpenAI key"); anything else is "Secret". A name already in use gets a number: "OpenAI key 2".
    public static func name(for value: String, existing: Set<String>) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isToken = !trimmed.isEmpty && !trimmed.contains(where: \.isWhitespace)
        let base = variableName(in: trimmed)
            ?? (isToken ? prefixes.first { trimmed.hasPrefix($0.prefix) }?.name : nil)
            ?? "Secret"
        guard existing.contains(base) else { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// The name in a one-line `NAME=value` or `export NAME=value`.
    static func variableName(in line: String) -> String? {
        guard !line.contains(where: \.isNewline) else { return nil }
        let assignment = line.hasPrefix("export ") ? String(line.dropFirst(7)) : line
        guard let equals = assignment.firstIndex(of: "=") else { return nil }
        let name = assignment[..<equals].trimmingCharacters(in: .whitespaces)
        let value = assignment[assignment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, (1...64).contains(name.count),
              name.first.map({ $0.isLetter || $0 == "_" }) == true,
              name.allSatisfy({ ($0.isLetter || $0.isNumber || $0 == "_") && $0.isASCII })
        else { return nil }
        return name
    }
}
