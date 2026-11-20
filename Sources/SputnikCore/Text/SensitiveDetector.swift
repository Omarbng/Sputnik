import Foundation

/// What kind of sensitive value a copy looks like. Safe to log (it says nothing of the value).
public enum SensitiveKind: String, Sendable {
    case apiKey, privateKey, token, cardNumber, iban, oneTimeCode
}

/// Spots copies that shouldn't sit in history for long: API keys and tokens, private keys,
/// card numbers (Luhn-checked), IBANs (checksum-checked) and one-time codes. Only the whole
/// copy counts, so a sentence that mentions a number doesn't.
public enum SensitiveDetector {
    /// How long a sensitive copy stays in history.
    public static let lifetime: TimeInterval = 10 * 60
    /// Sensitive values are short; longer text is never checked.
    static let maxLength = 4_096

    public static func kind(of text: String) -> SensitiveKind? {
        guard text.utf8.count <= maxLength else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 6 else { return nil }
        if value.contains("-----BEGIN"), value.contains("PRIVATE KEY-----") { return .privateKey }
        if let name = SecretNamer.variableName(in: value), isSecretName(name) { return .apiKey }
        guard !value.contains(where: \.isNewline) else { return nil }
        if isKnownKey(value) { return .apiKey }
        if isJWT(value) { return .token }
        if isCardNumber(value) { return .cardNumber }
        if isIBAN(value) { return .iban }
        if isOneTimeCode(value) { return .oneTimeCode }
        return nil
    }

    /// `OPENAI_API_KEY=…`, `DB_PASSWORD=…`, `export GITHUB_TOKEN=…`
    static func isSecretName(_ name: String) -> Bool {
        let upper = name.uppercased()
        return ["KEY", "TOKEN", "SECRET", "PASSWORD", "PASSWD", "PWD", "CREDENTIAL"].contains { upper.contains($0) }
    }

    /// A single token with a well-known prefix (`sk-…`, `ghp_…`, `AKIA…`), long enough to be real.
    static func isKnownKey(_ value: String) -> Bool {
        guard value.count >= 20, !value.contains(where: \.isWhitespace) else { return false }
        return SecretNamer.prefixes.contains { $0.prefix != "eyJ" && value.hasPrefix($0.prefix) }
    }

    /// header.payload.signature, base64url.
    static func isJWT(_ value: String) -> Bool {
        guard value.hasPrefix("eyJ"), value.count >= 30 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_="))
        return parts.count == 3 && parts.allSatisfy {
            !$0.isEmpty && $0.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
        }
    }

    /// 13–19 digits, optionally grouped with spaces or dashes, passing the Luhn check.
    static func isCardNumber(_ value: String) -> Bool {
        guard value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == " " || $0 == "-") }) else { return false }
        let digits = value.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            let (index, digit) = pair
            guard index % 2 == 1 else { return total + digit }
            let doubled = digit * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }

    /// Country code, check digits, then 11–30 letters or digits, passing the mod-97 check.
    static func isIBAN(_ value: String) -> Bool {
        let compact = value.replacingOccurrences(of: " ", with: "").uppercased()
        guard (15...34).contains(compact.count),
              compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              compact.prefix(2).allSatisfy(\.isLetter),
              compact.dropFirst(2).prefix(2).allSatisfy(\.isNumber)
        else { return false }
        let rearranged = compact.dropFirst(4) + compact.prefix(4)
        var remainder = 0
        for character in rearranged {
            let number = character.isLetter
                ? Int(character.asciiValue! - Character("A").asciiValue!) + 10
                : character.wholeNumberValue!
            for digit in String(number) {
                remainder = (remainder * 10 + digit.wholeNumberValue!) % 97
            }
        }
        return remainder == 1
    }

    /// 6–8 digits, optionally split in two halves ("123 456", "123-456"). Shorter numbers are
    /// too often years or amounts.
    static func isOneTimeCode(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        guard (6...8).contains(digits.count), digits.allSatisfy(\.isASCII) else { return false }
        if value == digits { return true }
        let halves = value.split(whereSeparator: { $0 == " " || $0 == "-" })
        return halves.count == 2 && halves.joined() == digits && value.count == digits.count + 1
    }
}
