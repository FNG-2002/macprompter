// Renders the text cards and captions for the demo video (docs/MEDIA.md).
//   swiftc -O scripts/media/PromoCards.swift -o build/promo-cards && build/promo-cards <out-dir> <icon.png> [screenshot.png caption name]...
import AppKit

let size = NSSize(width: 1920, height: 1080)
let canvas = NSColor(red: 0.075, green: 0.08, blue: 0.095, alpha: 1)
let accent = NSColor(red: 0.72, green: 0.67, blue: 1, alpha: 1)
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1], isDirectory: true)
let icon = NSImage(contentsOfFile: args[2])!

func render(_ name: String, opaque: Bool = true, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if opaque { canvas.setFill(); NSRect(origin: .zero, size: size).fill() }
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name + ".png"))
}

func text(_ string: String, _ font: NSFont, _ color: NSColor, centerY: CGFloat, width: CGFloat = 1500) {
    let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineSpacing = 6
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let bounds = attributed.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
    attributed.draw(with: NSRect(x: (size.width - width) / 2, y: centerY - bounds.height / 2, width: width, height: bounds.height), options: [.usesLineFragmentOrigin])
}

func card(_ name: String, title: String, subtitle: String, footer: String? = nil, showIcon: Bool = true) {
    render(name) {
        if showIcon { icon.draw(in: NSRect(x: (size.width - 200) / 2, y: 640, width: 200, height: 200)) }
        text(title, .systemFont(ofSize: 76, weight: .bold), .white, centerY: showIcon ? 540 : 600)
        text(subtitle, .systemFont(ofSize: 38, weight: .regular), NSColor(white: 0.78, alpha: 1), centerY: showIcon ? 430 : 470)
        if let footer { text(footer, .systemFont(ofSize: 30, weight: .semibold), accent, centerY: 300) }
    }
}

/// Bottom caption pill over the screen recording.
func caption(_ name: String, _ string: String) {
    render(name, opaque: false) {
        let font = NSFont.systemFont(ofSize: 40, weight: .semibold)
        let width = (string as NSString).size(withAttributes: [.font: font]).width + 90
        let pill = NSRect(x: (size.width - width) / 2, y: 70, width: width, height: 92)
        NSColor(white: 0, alpha: 0.78).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 46, yRadius: 46).fill()
        accent.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(roundedRect: pill.insetBy(dx: 1, dy: 1), xRadius: 45, yRadius: 45); border.lineWidth = 2; border.stroke()
        text(string, font, .white, centerY: pill.midY, width: width)
    }
}

/// App window screenshot on the canvas with a caption above it.
func shot(_ name: String, _ path: String, _ title: String) {
    let image = NSImage(contentsOfFile: path)!
    render(name) {
        text(title, .systemFont(ofSize: 44, weight: .semibold), .white, centerY: 985)
        let maxSize = NSSize(width: 1500, height: 860)
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height)
        let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(x: (size.width - drawn.width) / 2, y: 40 + (maxSize.height - drawn.height) / 2, width: drawn.width, height: drawn.height)
        let shadow = NSShadow(); shadow.shadowBlurRadius = 40; shadow.shadowColor = NSColor(white: 0, alpha: 0.6)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

card("card-title", title: "macprompter", subtitle: "Der Teleprompter an deiner Notch.\nLokal auf deinem Mac. Open Source.")
card("card-voice", title: "Oder einfach sprechen.", subtitle: "Im Modus Stimme folgt der Text deinen Worten –\nmit Apples Spracherkennung, komplett offline.", showIcon: false)
card("card-end", title: "macprompter 1.0", subtitle: "Kostenlos und Open Source (MIT) · macOS 26+", footer: "github.com/FNG-2002/macprompter")
caption("cap-1", "Der Prompter sitzt oben an der Kamera …")
caption("cap-2", "… und die Folien wechseln mit deinem Text")
caption("cap-3", "Maus über den Prompter: sofort Pause")
var rest = Array(args.dropFirst(3))
while rest.count >= 3 { shot(rest[2], rest[0], rest[1]); rest.removeFirst(3) }
