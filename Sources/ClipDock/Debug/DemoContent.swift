#if DEBUG
import AppKit
import ClipDockCore

/// Made-up clipboard history for screenshots (debug builds, demo history only). Every item is
/// invented: no real names, numbers or addresses.
@MainActor
enum DemoContent {
    private struct Item {
        let minutesAgo: Double
        let app: String
        let name: String
        let payload: ClipPayload
    }

    static func seed(capture: CaptureController, saved: SavedItems) {
        let items: [Item] = [
            Item(minutesAgo: 240, app: "com.apple.Terminal", name: "Terminal", payload: .text("git commit -m \"Fix the login redirect\"", rtf: nil)),
            Item(minutesAgo: 95, app: "com.apple.Notes", name: "Notes", payload: .text("Lunch with Anna on Friday at 1pm. Call +1 (555) 010-9999 if anything changes.", rtf: nil)),
            Item(minutesAgo: 41, app: "com.apple.Preview", name: "Preview", payload: .image(demoImage(), isPNG: true)),
            Item(minutesAgo: 18, app: "com.apple.mail", name: "Mail", payload: .text("Merci pour votre retour, on se voit demain à 10h.", rtf: nil)),
            Item(minutesAgo: 9, app: "net.whatsapp.WhatsApp", name: "WhatsApp", payload: .text("Привет! Отправлю договор сегодня вечером.", rtf: nil)),
            Item(minutesAgo: 5, app: "com.apple.Safari", name: "Safari", payload: .url("https://www.apple.com/macos/")),
            Item(minutesAgo: 2, app: "com.apple.MobileSMS", name: "Messages", payload: .text("Can we move the design review to Thursday at 4pm?", rtf: nil)),
        ]
        for item in items {
            capture.record(CapturedClip(
                payload: item.payload,
                sourceBundleID: item.app,
                sourceAppName: item.name,
                capturedAt: Date.now.addingTimeInterval(-item.minutesAgo * 60)
            ))
        }
        Task {
            _ = try? await saved.create(name: "Office address", value: "1 Infinite Loop, Cupertino, CA", secret: false)
            _ = try? await saved.create(name: "Email sign-off", value: "Best regards,\nAlex", secret: false)
            Log.app.notice("debug demo history seeded items=\(items.count + 2, privacy: .public)")
        }
    }

    /// A small landscape picture (a gradient sky over hills), drawn here.
    private static func demoImage() -> Data {
        let size = NSSize(width: 640, height: 400)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.40, alpha: 1), NSColor(red: 0.33, green: 0.36, blue: 0.75, alpha: 1)])?
                .draw(in: rect, angle: 90)
            NSColor(red: 0.16, green: 0.20, blue: 0.36, alpha: 1).setFill()
            let hills = NSBezierPath()
            hills.move(to: .zero)
            hills.curve(to: NSPoint(x: 640, y: 120), controlPoint1: NSPoint(x: 180, y: 220), controlPoint2: NSPoint(x: 420, y: 40))
            hills.line(to: NSPoint(x: 640, y: 0))
            hills.close()
            hills.fill()
            NSColor(white: 1, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 450, y: 250, width: 70, height: 70)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}
#endif
