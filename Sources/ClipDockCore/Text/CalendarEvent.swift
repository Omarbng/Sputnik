import Foundation

/// A one-event iCalendar file. Opening it in Calendar shows Calendar's own "add event" window,
/// so Omar picks the calendar and confirms; ClipDock never writes to his calendars itself.
public struct CalendarEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var duration: TimeInterval
    public var notes: String?

    /// Events without a stated length last an hour.
    public static let defaultDuration: TimeInterval = 3_600

    public init(title: String, start: Date, duration: TimeInterval?, notes: String?) {
        self.title = title
        self.start = start
        self.duration = duration ?? Self.defaultDuration
        self.notes = notes
    }

    /// From a copied text: the first line becomes the title (at most 80 characters).
    public static func from(text: String, contacts: DetectedContacts) -> CalendarEvent? {
        guard let date = contacts.date else { return nil }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = String(firstLine.trimmingCharacters(in: .whitespaces).prefix(80))
        let notes = text.count > title.count ? String(text.prefix(2_000)) : nil
        return CalendarEvent(title: title.isEmpty ? "Event" : title, start: date, duration: contacts.duration, notes: notes)
    }

    public func ics(uid: String, now: Date) -> String {
        [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//ClipDock//EN",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(Self.utc(now))",
            "DTSTART:\(Self.utc(start))",
            "DTEND:\(Self.utc(start.addingTimeInterval(duration)))",
            "SUMMARY:\(Self.escape(title))",
        ]
        .appending(contentsOf: notes.map { ["DESCRIPTION:\(Self.escape($0))"] } ?? [])
        .appending(contentsOf: ["END:VEVENT", "END:VCALENDAR"])
        .joined(separator: "\r\n") + "\r\n"
    }

    static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// RFC 5545 text escaping.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

private extension Array {
    func appending(contentsOf other: [Element]) -> [Element] { self + other }
}
