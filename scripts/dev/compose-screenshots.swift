// Turns raw app snapshots (from the debug hooks, made-up demo history) into the README images:
// each view on a soft gradient with a caption, plus an animated tour.
//
//   swift scripts/dev/compose-screenshots.swift <snapshot folder> docs/images
//
// Expects popup-dark.png, actions-dark.png, translate-row-dark.png, card-dark.png, hud-dark.png,
// pill-dark-0…9.png, pill-dark-translate.png, pill-dark-command.png, guide-dark.png,
// setup-welcome-dark.png, setup-languages-dark.png, and the -light versions of popup and card.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: compose-screenshots.swift <snapshots> <out>"); exit(1) }
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func load(_ name: String) -> NSBitmapImageRep? {
    guard let data = try? Data(contentsOf: input.appending(path: name + ".png")) else {
        print("missing \(name)"); return nil
    }
    return NSBitmapImageRep(data: data)
}

/// Draws into a new bitmap of `size` pixels.
func canvas(_ size: CGSize, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A deep, quiet backdrop with two soft glows (dark) or a warm paper one (light).
func backdrop(_ c: CGContext, _ size: CGSize, dark: Bool) {
    let space = CGColorSpaceCreateDeviceRGB()
    let base = dark ? [color(0x0B0C12), color(0x15131F)] : [color(0xF5F3FA), color(0xFBF7F1)]
    let linear = CGGradient(colorsSpace: space, colors: base as CFArray, locations: [0, 1])!
    c.drawLinearGradient(linear, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
    let glows: [(CGPoint, UInt32, CGFloat)] = dark
        ? [(CGPoint(x: size.width * 0.18, y: size.height * 0.85), 0x4F46E5, 0.30), (CGPoint(x: size.width * 0.88, y: size.height * 0.12), 0x14B8A6, 0.16)]
        : [(CGPoint(x: size.width * 0.15, y: size.height * 0.85), 0xC4B5FD, 0.45), (CGPoint(x: size.width * 0.9, y: size.height * 0.1), 0xFDBA74, 0.35)]
    for (center, hex, alpha) in glows {
        let radial = CGGradient(colorsSpace: space, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(radial, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(size.width, size.height) * 0.55, options: [])
    }
}

/// Places a snapshot, scaled by `scale`, centred on `center`. Opaque window snapshots (Settings,
/// setup, the guide) get rounded corners and a shadow, like a window.
func place(_ c: CGContext, _ rep: NSBitmapImageRep, center: CGPoint, scale: CGFloat, window: Bool = false) {
    guard let image = rep.cgImage else { return }
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    c.saveGState()
    if window {
        let path = CGPath(roundedRect: rect, cornerWidth: 22 * scale * 2, cornerHeight: 22 * scale * 2, transform: nil)
        c.setShadow(offset: CGSize(width: 0, height: -24 * scale * 2), blur: 60 * scale * 2, color: color(0x000000, 0.45))
        c.addPath(path); c.setFillColor(color(0x000000)); c.fillPath()
        c.setShadow(offset: .zero, blur: 0, color: nil)
        c.addPath(path); c.clip()
    }
    c.interpolationQuality = .high
    c.draw(image, in: rect)
    c.restoreGState()
}

/// "⌥⌥  Your clipboard history, at the cursor": the keys in a keycap, then the words.
func caption(_ c: CGContext, keys: String, text: String, at origin: CGPoint, size: CGFloat, dark: Bool) {
    let ink = dark ? NSColor(white: 0.97, alpha: 1) : NSColor(white: 0.08, alpha: 1)
    let muted = dark ? NSColor(white: 0.72, alpha: 1) : NSColor(white: 0.32, alpha: 1)
    let keyFont = NSFont.systemFont(ofSize: size, weight: .semibold)
    let keyString = NSAttributedString(string: keys, attributes: [.font: keyFont, .foregroundColor: ink])
    let keySize = keyString.size()
    let pad = size * 0.55
    let cap = CGRect(x: origin.x, y: origin.y - size * 0.35, width: keySize.width + pad * 2, height: keySize.height + size * 0.5)
    let path = NSBezierPath(roundedRect: cap, xRadius: size * 0.42, yRadius: size * 0.42)
    (dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.05)).setFill(); path.fill()
    (dark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.16)).setStroke(); path.lineWidth = size / 16; path.stroke()
    keyString.draw(at: CGPoint(x: cap.minX + pad, y: cap.minY + size * 0.25))
    NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: muted])
        .draw(at: CGPoint(x: cap.maxX + size * 0.6, y: cap.minY + size * 0.25))
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try? rep.representation(using: .png, properties: [:])?.write(to: output.appending(path: name))
    print("wrote \(name)")
}

// MARK: Hero (dark and light): the popup, the translation card and the dictation bar.

for mode in ["dark", "light"] {
    let dark = mode == "dark"
    guard let popup = load("popup-\(mode)"), let card = load("card-\(mode)"), let pill = load("pill-\(mode)-translate") ?? load("pill-\(mode)-4") else { continue }
    let size = CGSize(width: 2400, height: 1400)
    save(canvas(size) { c in
        backdrop(c, size, dark: dark)
        place(c, popup, center: CGPoint(x: size.width * 0.33, y: size.height * 0.5), scale: 1.0)
        place(c, card, center: CGPoint(x: size.width * 0.72, y: size.height * 0.64), scale: 1.0)
        place(c, pill, center: CGPoint(x: size.width * 0.72, y: size.height * 0.28), scale: 1.25)
    }, "hero-\(mode).png")
}

// MARK: Feature images (dark), each with its keys.

let features: [(file: String, keys: String, text: String, shot: String, scale: CGFloat, window: Bool)] = [
    ("clipboard.png", "⌥ ⌥", "Your clipboard history, at the cursor", "popup-dark", 1.0, false),
    ("actions.png", "⌘ K", "Actions for any item", "actions-dark", 1.0, false),
    ("translate.png", "⌃ ⌃", "Translate selected text, in any app", "card-dark", 1.25, false),
    ("quick-look.png", "⇧ Space", "See the whole item", "peek-dark", 1.0, false),
    ("shortcuts.png", "Menu bar", "Shortcuts… lists every key", "guide-dark", 0.8, true),
]
for feature in features {
    guard let shot = load(feature.shot) else { continue }
    let size = CGSize(width: 1800, height: 1200)
    save(canvas(size) { c in
        backdrop(c, size, dark: true)
        place(c, shot, center: CGPoint(x: size.width / 2, y: size.height * 0.45), scale: feature.scale, window: feature.window)
        caption(c, keys: feature.keys, text: feature.text, at: CGPoint(x: 90, y: size.height - 120), size: 44, dark: true)
    }, feature.file)
}

// Dictation: the three colours of the bar.
if let plain = load("pill-dark-4"), let blue = load("pill-dark-translate"), let amber = load("pill-dark-command") {
    let size = CGSize(width: 1800, height: 1200)
    save(canvas(size) { c in
        backdrop(c, size, dark: true)
        let rows: [(NSBitmapImageRep, String, String)] = [
            (plain, "hold fn", "Talk, and it's typed where you are"),
            (blue, "fn + ⇧", "Talk in English, typed in another language"),
            (amber, "fn + ⌃", "Tell it what to do with the selected text"),
        ]
        for (index, row) in rows.enumerated() {
            let y = size.height * (0.72 - CGFloat(index) * 0.24)
            place(c, row.0, center: CGPoint(x: size.width * 0.27, y: y), scale: 1.6)
            caption(c, keys: row.1, text: row.2, at: CGPoint(x: size.width * 0.45, y: y - 12), size: 40, dark: true)
        }
    }, "dictation.png")
}

// Setup: the first two pages side by side.
if let welcome = load("setup-welcome-dark"), let languages = load("setup-languages-dark") {
    let size = CGSize(width: 2600, height: 1500)
    save(canvas(size) { c in
        backdrop(c, size, dark: true)
        place(c, welcome, center: CGPoint(x: size.width * 0.28, y: size.height * 0.5), scale: 1.0, window: true)
        place(c, languages, center: CGPoint(x: size.width * 0.72, y: size.height * 0.5), scale: 1.0, window: true)
    }, "setup.png")
}

// MARK: Animated tour

struct Frame { let rep: NSBitmapImageRep; let seconds: Double }
var frames: [Frame] = []
let tourSize = CGSize(width: 1200, height: 760)
func slide(_ shot: String, keys: String, text: String, scale: CGFloat, seconds: Double, window: Bool = false) {
    guard let rep = load(shot) else { return }
    frames.append(Frame(rep: canvas(tourSize) { c in
        backdrop(c, tourSize, dark: true)
        place(c, rep, center: CGPoint(x: tourSize.width / 2, y: tourSize.height * 0.44), scale: scale, window: window)
        caption(c, keys: keys, text: text, at: CGPoint(x: 56, y: tourSize.height - 84), size: 30, dark: true)
    }, seconds: seconds))
}
slide("popup-dark", keys: "⌥ ⌥", text: "Your clipboard history, at the cursor", scale: 0.62, seconds: 2.4)
slide("actions-dark", keys: "⌘ K", text: "Actions for any item", scale: 0.62, seconds: 2.0)
slide("translate-row-dark", keys: "⌘ T", text: "Translate an item, ↩ pastes it", scale: 0.62, seconds: 2.0)
slide("card-dark", keys: "⌃ ⌃", text: "Translate selected text, in any app", scale: 0.8, seconds: 2.4)
for round in 0..<2 {
    for index in 0..<10 {
        slide("pill-dark-\(index)", keys: "hold fn", text: "Talk, and it's typed for you", scale: 1.3, seconds: round == 1 && index == 9 ? 0.6 : 0.13)
    }
}
slide("pill-dark-translate", keys: "fn + ⇧", text: "…or typed in another language", scale: 1.3, seconds: 1.8)
slide("hud-dark", keys: "⇧ ⇧", text: "Proofread selected text in place", scale: 1.1, seconds: 2.0)
slide("guide-dark", keys: "Menu bar", text: "Shortcuts… lists every key", scale: 0.55, seconds: 2.4, window: true)

if !frames.isEmpty {
    let url = output.appending(path: "tour.gif") as CFURL
    let gif = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in frames {
        guard let image = frame.rep.cgImage else { continue }
        CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.seconds]] as CFDictionary)
    }
    CGImageDestinationFinalize(gif)
    print("wrote tour.gif (\(frames.count) frames)")
}
