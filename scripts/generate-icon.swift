import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift <iconset-directory>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func makeIcon(pixels: Int) -> NSImage {
    let scale = CGFloat(pixels) / 512
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()

    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    canvas.fill()

    let background = NSBezierPath(
        roundedRect: canvas.insetBy(dx: 28 * scale, dy: 28 * scale),
        xRadius: 112 * scale,
        yRadius: 112 * scale
    )
    NSGradient(colors: [
        NSColor(red: 0.18, green: 0.14, blue: 0.27, alpha: 1),
        NSColor(red: 0.08, green: 0.07, blue: 0.13, alpha: 1),
    ])?.draw(in: background, angle: -45)

    let back = NSBezierPath(
        roundedRect: NSRect(x: 112, y: 210, width: 236, height: 164).applying(.init(scaleX: scale, y: scale)),
        xRadius: 30 * scale,
        yRadius: 30 * scale
    )
    NSColor(red: 0.56, green: 0.43, blue: 0.92, alpha: 1).setFill()
    back.fill()

    let front = NSBezierPath(
        roundedRect: NSRect(x: 164, y: 138, width: 236, height: 164).applying(.init(scaleX: scale, y: scale)),
        xRadius: 30 * scale,
        yRadius: 30 * scale
    )
    NSColor(red: 0.43, green: 0.91, blue: 0.84, alpha: 1).setFill()
    front.fill()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 210 * scale, y: 220 * scale))
    arrow.line(to: NSPoint(x: 334 * scale, y: 220 * scale))
    arrow.move(to: NSPoint(x: 302 * scale, y: 250 * scale))
    arrow.line(to: NSPoint(x: 334 * scale, y: 220 * scale))
    arrow.line(to: NSPoint(x: 302 * scale, y: 190 * scale))
    arrow.lineWidth = max(1.2, 20 * scale)
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(red: 0.11, green: 0.09, blue: 0.17, alpha: 1).setStroke()
    arrow.stroke()

    image.unlockFocus()
    return image
}

for variant in variants {
    let image = makeIcon(pixels: variant.pixels)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("Could not render \(variant.name)\n", stderr)
        exit(1)
    }
    try png.write(to: outputDirectory.appendingPathComponent(variant.name))
}
