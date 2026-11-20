import Foundation

/// A phone number, email address, or date found in a copied text, for the actions menu
/// (Message on WhatsApp, Call, Email, Add to Calendar).
public struct DetectedContacts: Equatable, Sendable {
    public var phone: String?
    public var email: String?
    public var date: Date?
    /// Seconds, when the text gave a range ("3–4 pm").
    public var duration: TimeInterval?
    public var timeZone: TimeZone?

    public init(phone: String? = nil, email: String? = nil, date: Date? = nil, duration: TimeInterval? = nil, timeZone: TimeZone? = nil) {
        self.phone = phone
        self.email = email
        self.date = date
        self.duration = duration
        self.timeZone = timeZone
    }

    public var isEmpty: Bool { phone == nil && email == nil && date == nil }
}

public enum ContactDetector {
    /// Only the start of a long text is scanned, so the menu opens instantly.
    static let scanLength = 2_000

    public static func detect(in text: String) -> DetectedContacts {
        let sample = String(text.prefix(scanLength))
        var found = DetectedContacts()
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .date]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return found }
        let range = NSRange(sample.startIndex..., in: sample)
        for match in detector.matches(in: sample, options: [], range: range) {
            switch match.resultType {
            case .phoneNumber where found.phone == nil:
                if let number = match.phoneNumber, whatsAppNumber(from: number) != nil { found.phone = number }
            case .link where found.email == nil:
                if let url = match.url, url.scheme?.lowercased() == "mailto" {
                    found.email = String(url.absoluteString.dropFirst("mailto:".count))
                        .removingPercentEncoding
                }
            case .date where found.date == nil:
                found.date = match.date
                found.duration = match.duration > 0 ? match.duration : nil
                found.timeZone = match.timeZone
            default:
                break
            }
        }
        return found
    }

    /// The number as WhatsApp wants it: digits only, with the country code and without "+"
    /// or a leading "00". Nil for anything too short to be a phone number.
    public static func whatsAppNumber(from phone: String) -> String? {
        var digits = phone.filter { $0.isASCII && $0.isNumber }
        if !phone.trimmingCharacters(in: .whitespaces).hasPrefix("+"), digits.hasPrefix("00") {
            digits.removeFirst(2)
        }
        return (7...15).contains(digits.count) ? digits : nil
    }

    /// `tel:` keeps a leading "+", and digits only.
    public static func telNumber(from phone: String) -> String {
        let plus = phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : ""
        return plus + phone.filter { $0.isASCII && $0.isNumber }
    }
}
