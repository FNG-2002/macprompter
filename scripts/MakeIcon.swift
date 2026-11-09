import AppKit
// swift scripts/MakeIcon.swift <iconset-folder>          macOS icon PNGs
// swift scripts/MakeIcon.swift --ios <AppIcon.png>       full-bleed 1024 px iOS icon (the system applies the mask)
let ios = CommandLine.arguments[1] == "--ios"
let destination = CommandLine.arguments[ios ? 2 : 1]

func drawIcon(fullBleed: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.80, green: 0.76, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.46, green: 0.40, blue: 0.80, alpha: 1))!
    if fullBleed { gradient.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -60) }
    else { gradient.draw(in: NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 194, yRadius: 194), angle: -60) }
    NSColor(calibratedRed: 0.065, green: 0.067, blue: 0.09, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 240, y: 230, width: 544, height: 580), xRadius: 95, yRadius: 95).fill()
    NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 405, y: 760, width: 214, height: 82), xRadius: 26, yRadius: 26).fill()
    for (index, width) in [340.0, 290.0, 340.0, 215.0].enumerated() {
        (index == 0 ? NSColor(calibratedRed: 0.76, green: 0.71, blue: 1, alpha: 1) : NSColor(calibratedWhite: 0.8, alpha: 1)).setFill()
        NSBezierPath(roundedRect: NSRect(x: 342, y: 623 - Double(index) * 87, width: width, height: 27), xRadius: 13.5, yRadius: 13.5).fill()
    }
    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int, opaque: Bool) -> Data {
    // iOS icons must not carry an alpha channel.
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

if ios {
    try png(drawIcon(fullBleed: true), pixels: 1024, opaque: true).write(to: URL(fileURLWithPath: destination))
} else {
    let image = drawIcon(fullBleed: false)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            try png(image, pixels: size * scale, opaque: false).write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
}
