import AppKit
import ClipDockCore

/// Message on WhatsApp, Call, Write Email, and Add to Calendar for a phone number, address,
/// or date found in a copied text. Each hands over to the app that does it; ClipDock itself
/// sends nothing and writes nothing outside its own folder.
@MainActor
final class ContactActions {
    private let hud: HUDController

    init(hud: HUDController) {
        self.hud = hud
    }

    /// Opens a chat with the number in the WhatsApp app, without saving a contact.
    func whatsApp(_ phone: String) {
        guard let number = ContactDetector.whatsAppNumber(from: phone) else { return }
        let app = URL(string: "whatsapp://send?phone=\(number)")!
        let web = URL(string: "https://wa.me/\(number)")!
        // Without the WhatsApp app, the browser's wa.me page offers to open it.
        NSWorkspace.shared.open(NSWorkspace.shared.urlForApplication(toOpen: app) != nil ? app : web)
        Log.paste.notice("contact action=whatsApp")
    }

    /// FaceTime (or the iPhone, through Continuity) asks before it calls.
    func call(_ phone: String) {
        guard let url = URL(string: "tel:\(ContactDetector.telNumber(from: phone))") else { return }
        NSWorkspace.shared.open(url)
        Log.paste.notice("contact action=call")
    }

    func email(_ address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? address
        guard let url = URL(string: "mailto:\(encoded)") else { return }
        NSWorkspace.shared.open(url)
        Log.paste.notice("contact action=email")
    }

    /// Calendar opens the event in its own "add event" window, where Omar picks the calendar
    /// and confirms. The temporary .ics file is deleted a minute later.
    func addToCalendar(text: String, contacts: DetectedContacts) {
        guard let event = CalendarEvent.from(text: text, contacts: contacts) else { return }
        do {
            let data = Data(event.ics(uid: UUID().uuidString, now: .now).utf8)
            let file = try ImageActions.export(data, named: "Event \(UUID().uuidString.prefix(8)).ics")
            let calendar = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal")
            if let calendar {
                NSWorkspace.shared.open([file], withApplicationAt: calendar, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(file)
            }
            Task {
                try? await Task.sleep(for: .seconds(60))
                try? FileManager.default.removeItem(at: file)
            }
            Log.paste.notice("contact action=calendar")
        } catch {
            hud.show("Couldn't create the event", style: .error)
        }
    }
}
