import AppKit

enum AppIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()

        let background = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 28, dy: 28),
            xRadius: 112,
            yRadius: 112
        )
        NSGradient(colors: [
            NSColor(red: 0.17, green: 0.13, blue: 0.25, alpha: 1),
            NSColor(red: 0.08, green: 0.07, blue: 0.13, alpha: 1),
        ])?.draw(in: background, angle: -45)

        let backWindow = NSBezierPath(
            roundedRect: NSRect(x: 118, y: 205, width: 230, height: 164),
            xRadius: 30,
            yRadius: 30
        )
        NSColor(red: 0.56, green: 0.43, blue: 0.92, alpha: 1).setFill()
        backWindow.fill()

        let frontWindow = NSBezierPath(
            roundedRect: NSRect(x: 166, y: 139, width: 230, height: 164),
            xRadius: 30,
            yRadius: 30
        )
        NSColor(red: 0.43, green: 0.91, blue: 0.84, alpha: 1).setFill()
        frontWindow.fill()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 210, y: 221))
        arrow.line(to: NSPoint(x: 332, y: 221))
        arrow.move(to: NSPoint(x: 298, y: 251))
        arrow.line(to: NSPoint(x: 332, y: 221))
        arrow.line(to: NSPoint(x: 298, y: 191))
        arrow.lineWidth = 20
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        NSColor(red: 0.11, green: 0.09, blue: 0.17, alpha: 1).setStroke()
        arrow.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
