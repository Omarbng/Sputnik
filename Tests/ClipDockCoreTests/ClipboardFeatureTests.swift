import Foundation
import Testing
@testable import ClipDockCore

@Suite("Clean links")
struct LinkCleanerTests {
    @Test("Tracking parameters go; the rest of the link stays as it was")
    func removesTracking() {
        #expect(LinkCleaner.clean("https://example.com/page?utm_source=news&utm_medium=email&id=42") == "https://example.com/page?id=42")
        #expect(LinkCleaner.clean("https://example.com/a?fbclid=123") == "https://example.com/a")
        #expect(LinkCleaner.clean("https://example.com/a?utm_source=x#section") == "https://example.com/a#section")
        #expect(LinkCleaner.clean("https://example.com/search?q=hello%20world&gclid=abc") == "https://example.com/search?q=hello%20world")
        #expect(LinkCleaner.clean("  https://shop.example.com/?UTM_Campaign=x&ref=friend  ") == "https://shop.example.com/?ref=friend")
    }

    @Test("Site-specific parameters only on their sites")
    func siteSpecific() {
        #expect(LinkCleaner.clean("https://www.youtube.com/watch?v=abc123&si=XYZ") == "https://www.youtube.com/watch?v=abc123")
        #expect(LinkCleaner.clean("https://youtu.be/abc123?si=XYZ") == "https://youtu.be/abc123")
        #expect(LinkCleaner.clean("https://example.com/?si=keep") == nil)
    }

    @Test("Nothing to clean, or not a link")
    func nothingToDo() {
        #expect(LinkCleaner.clean("https://example.com/a") == nil)
        #expect(LinkCleaner.clean("https://example.com/a?id=1") == nil)
        #expect(LinkCleaner.clean("not a link utm_source=x") == nil)
        #expect(LinkCleaner.clean("see https://example.com/?utm_source=x") == nil)
    }
}

@Suite("Sensitive copies")
struct SensitiveDetectorTests {
    @Test("Keys, tokens and private keys")
    func keys() {
        #expect(SensitiveDetector.kind(of: "sk-proj-abcdefghijklmnopqrstuvwxyz123456") == .apiKey)
        #expect(SensitiveDetector.kind(of: "ghp_abcdefghijklmnopqrstuvwxyz0123456789\n") == .apiKey)
        #expect(SensitiveDetector.kind(of: "OPENAI_API_KEY=sk-abc") == .apiKey)
        #expect(SensitiveDetector.kind(of: "export DB_PASSWORD=hunter2") == .apiKey)
        #expect(SensitiveDetector.kind(of: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcDEF123_-xyz") == .token)
        #expect(SensitiveDetector.kind(of: "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----") == .privateKey)
    }

    @Test("Card numbers pass Luhn; IBANs pass mod 97")
    func numbers() {
        #expect(SensitiveDetector.kind(of: "4111 1111 1111 1111") == .cardNumber)
        #expect(SensitiveDetector.kind(of: "4111-1111-1111-1111") == .cardNumber)
        #expect(SensitiveDetector.kind(of: "4111 1111 1111 1112") == nil)
        #expect(SensitiveDetector.kind(of: "GB82 WEST 1234 5698 7654 32") == .iban)
        #expect(SensitiveDetector.kind(of: "DE89370400440532013000") == .iban)
        #expect(SensitiveDetector.kind(of: "GB82 WEST 1234 5698 7654 33") == nil)
    }

    @Test("One-time codes are 6–8 digits on their own")
    func codes() {
        #expect(SensitiveDetector.kind(of: "482913") == .oneTimeCode)
        #expect(SensitiveDetector.kind(of: "482 913") == .oneTimeCode)
        #expect(SensitiveDetector.kind(of: "2026") == nil)
        #expect(SensitiveDetector.kind(of: "12345") == nil)
        #expect(SensitiveDetector.kind(of: "Your code is 482913") == nil)
    }

    @Test("Ordinary text isn't sensitive")
    func ordinary() {
        #expect(SensitiveDetector.kind(of: "hello world") == nil)
        #expect(SensitiveDetector.kind(of: "NAME=Omar") == nil)
        #expect(SensitiveDetector.kind(of: "https://example.com/?a=1") == nil)
        #expect(SensitiveDetector.kind(of: String(repeating: "4", count: 5_000)) == nil)
    }
}

@Suite("Sensitive copies leave history")
struct SensitiveExpiryTests {
    @Test("An expired sensitive copy is removed; others stay")
    func expires() throws {
        let history = try TemporaryHistory()
        var key = textClip("sk-proj-abcdefghijklmnopqrstuvwxyz123456")
        key.expiresAt = referenceNow.addingTimeInterval(600)
        let stored = try history.database.ingest(key, retention: RetentionPolicy())
        _ = try history.database.ingest(textClip("plain", at: referenceNow.addingTimeInterval(1)), retention: RetentionPolicy())
        #expect(try history.database.applyRetention(RetentionPolicy(), now: referenceNow.addingTimeInterval(599)).isEmpty)
        #expect(try history.database.applyRetention(RetentionPolicy(), now: referenceNow.addingTimeInterval(600)) == [stored.item.id!])
        #expect(try history.database.allItems().map(\.text) == ["plain"])
    }

    @Test("Saving it (⌘P) keeps it; copying it again restarts the countdown")
    func pinAndRecopy() throws {
        let history = try TemporaryHistory()
        var key = textClip("482913")
        key.expiresAt = referenceNow.addingTimeInterval(600)
        let first = try history.database.ingest(key, retention: RetentionPolicy())
        var again = textClip("482913", at: referenceNow.addingTimeInterval(300))
        again.expiresAt = referenceNow.addingTimeInterval(900)
        let second = try history.database.ingest(again, retention: RetentionPolicy())
        #expect(second.wasDuplicate)
        #expect(second.item.expiresAt == referenceNow.addingTimeInterval(900))
        let pinned = try history.database.setPinned(true, id: first.item.id!)
        #expect(pinned?.expiresAt == nil)
        #expect(try history.database.applyRetention(RetentionPolicy(), now: referenceNow.addingTimeInterval(10_000)).isEmpty)
    }
}

@Suite("Phone numbers, emails and dates")
struct ContactDetectorTests {
    @Test("Finds them in copied text")
    func detects() {
        let phone = ContactDetector.detect(in: "Call me at +44 20 7946 0958 tomorrow")
        #expect(phone.phone != nil)
        #expect(phone.phone.flatMap(ContactDetector.whatsAppNumber) == "442079460958")
        #expect(ContactDetector.detect(in: "write to omar.test@example.com please").email == "omar.test@example.com")
        #expect(ContactDetector.detect(in: "Lunch on November 21, 2026 at 1pm").date != nil)
        #expect(ContactDetector.detect(in: "hello there").isEmpty)
    }

    @Test("WhatsApp and tel: numbers")
    func numbers() {
        #expect(ContactDetector.whatsAppNumber(from: "0044 20 7946 0958") == "442079460958")
        #expect(ContactDetector.whatsAppNumber(from: "+7 (912) 345-67-89") == "79123456789")
        #expect(ContactDetector.whatsAppNumber(from: "12") == nil)
        #expect(ContactDetector.telNumber(from: "+1 (555) 010-9999") == "+15550109999")
    }

    @Test("Text with a phone number gets WhatsApp and Call in the menu")
    func menu() {
        let item = ClipItem(id: 1, kind: .text, text: "Anna +44 20 7946 0958", contentHash: "h", byteSize: 1, createdAt: referenceNow, lastUsedAt: referenceNow)
        let actions = ClipAction.available(for: item)
        #expect(actions.contains(.whatsApp) && actions.contains(.call))
        #expect(!actions.contains(.email))
    }
}

@Suite("Calendar events")
struct CalendarEventTests {
    @Test("A one-event iCalendar file, escaped, an hour long by default")
    func ics() {
        let event = CalendarEvent(title: "Lunch with Anna, downtown", start: referenceNow, duration: nil, notes: nil)
        let ics = event.ics(uid: "u1", now: referenceNow)
        #expect(ics.contains("SUMMARY:Lunch with Anna\\, downtown\r\n"))
        #expect(ics.contains("DTSTART:20270115T080000Z\r\n"))
        #expect(ics.contains("DTEND:20270115T090000Z\r\n"))
        #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n") && ics.hasSuffix("END:VCALENDAR\r\n"))
    }

    @Test("Built from copied text: the first line is the title")
    func fromText() {
        let contacts = DetectedContacts(date: referenceNow)
        let event = CalendarEvent.from(text: "Board meeting\nRoom 4, bring the slides", contacts: contacts)
        #expect(event?.title == "Board meeting")
        #expect(event?.notes != nil)
        #expect(CalendarEvent.from(text: "no date", contacts: DetectedContacts()) == nil)
    }
}

@Suite("Reply in their language")
struct ReplyLanguageMemoryTests {
    @Test("After French → English, English goes into French for an hour")
    func remembers() {
        var memory = ReplyLanguageMemory()
        #expect(memory.englishTarget(default: .russian, now: referenceNow) == .russian)
        memory.noteTranslation(from: .french, at: referenceNow)
        #expect(memory.englishTarget(default: .russian, now: referenceNow.addingTimeInterval(600)) == .french)
        #expect(memory.isActive(now: referenceNow, default: .russian))
        #expect(memory.englishTarget(default: .russian, now: referenceNow.addingTimeInterval(3_601)) == .russian)
    }

    @Test("English sources don't change it; the latest foreign language wins")
    func latestWins() {
        var memory = ReplyLanguageMemory()
        memory.noteTranslation(from: .russian, at: referenceNow)
        memory.noteTranslation(from: .english, at: referenceNow.addingTimeInterval(10))
        #expect(memory.englishTarget(default: .french, now: referenceNow.addingTimeInterval(20)) == .russian)
        memory.noteTranslation(from: .french, at: referenceNow.addingTimeInterval(30))
        #expect(memory.englishTarget(default: .russian, now: referenceNow.addingTimeInterval(40)) == .french)
        #expect(!memory.isActive(now: referenceNow.addingTimeInterval(40), default: .french))
    }
}

@Suite("Paste stack")
struct PasteStackTests {
    @Test("Needs two items; advances in order and finishes")
    func order() {
        #expect(PasteStack(ids: [1]) == nil)
        var stack = PasteStack(ids: [7, 3, 9])!
        #expect(stack.current == 7 && stack.progress == "1 of 3")
        #expect(stack.advance() == 3)
        #expect(stack.progress == "2 of 3")
        #expect(stack.advance() == 9)
        #expect(stack.advance() == nil)
        #expect(stack.isFinished)
    }
}

@Suite("Popup keys for Quick Look and the paste stack")
struct NewPopupKeyTests {
    @Test("⇧Space and ⌘Y peek; ⇧⌘↩ starts a paste stack")
    func keys() {
        #expect(PopupKeymap.command(keyCode: 0x31, modifiers: .shift) == .peek)
        #expect(PopupKeymap.command(keyCode: 0x10, modifiers: .command) == .peek)
        #expect(PopupKeymap.command(keyCode: 0x24, modifiers: [.command, .shift]) == .pasteOneByOne)
        #expect(PopupKeymap.command(keyCode: 0x24, modifiers: .command) == .pasteMarked)
    }

    @Test("Images get the image tools; writing actions only when Apple Intelligence is on")
    func menus() {
        let image = ClipItem(id: 1, kind: .image, text: nil, imageBlob: "a.png", contentHash: "h", byteSize: 1, createdAt: referenceNow, lastUsedAt: referenceNow)
        #expect(ClipAction.available(for: image).contains(.copyText))
        #expect(ClipAction.available(for: image).contains(.removeBackground))
        let text = ClipItem(id: 2, kind: .text, text: "hello", contentHash: "t", byteSize: 1, createdAt: referenceNow, lastUsedAt: referenceNow)
        #expect(!ClipAction.available(for: text).contains(.proofread))
        #expect(ClipAction.available(for: text, context: .init(writingTools: true)).contains(.proofread))
        let heic = ClipItem(id: 3, kind: .file, text: "/Users/x/IMG_1.HEIC", contentHash: "f", byteSize: 1, createdAt: referenceNow, lastUsedAt: referenceNow)
        #expect(ClipAction.available(for: heic).contains(.copyAsJPEG))
        let pdf = ClipItem(id: 4, kind: .file, text: "/Users/x/a.pdf", contentHash: "p", byteSize: 1, createdAt: referenceNow, lastUsedAt: referenceNow)
        #expect(!ClipAction.available(for: pdf).contains(.copyAsJPEG))
    }
}
