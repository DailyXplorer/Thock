import AppKit

/// The menu bar icon: a keycap with sound waves, drawn as a monochrome template image.
enum MenuBarIcon {
    enum State: CaseIterable {
        case on
        case off
        case muted
        case attention
    }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Template alpha survives in the menu bar, so an automatic mute reads as a dimmed icon, unlike the slashed manual off.
            context.setAlpha(state == .muted ? 0.45 : 1)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawKeycap(in: CGRect(x: 1, y: 2, width: 13, height: 12))
            if state == .attention {
                drawBadge(at: CGPoint(x: 17, y: 5))
            } else {
                drawWaves(from: CGPoint(x: 15.5, y: 8))
            }
            if state == .off { drawSlash(in: rect) }
            context.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Thock"
        return image
    }

    private static func drawKeycap(in rect: CGRect) {
        NSColor.black.set()
        let skirt = NSBezierPath(roundedRect: rect.insetBy(dx: 0.7, dy: 0.7), xRadius: 3.2, yRadius: 3.2)
        skirt.lineWidth = 1.4
        skirt.stroke()
        // The top face sits high in the skirt, with short bevels to the lower corners, so the shape reads as a keycap and not a button.
        let face = CGRect(x: rect.minX + 3, y: rect.minY + 2.2, width: rect.width - 6, height: rect.height - 6.6)
        let outline = NSBezierPath(roundedRect: face, xRadius: 1.6, yRadius: 1.6)
        outline.lineWidth = 1.1
        outline.stroke()
        let bevels = NSBezierPath()
        bevels.move(to: CGPoint(x: face.minX + 0.4, y: face.maxY - 0.4))
        bevels.line(to: CGPoint(x: rect.minX + 1.6, y: rect.maxY - 1.6))
        bevels.move(to: CGPoint(x: face.maxX - 0.4, y: face.maxY - 0.4))
        bevels.line(to: CGPoint(x: rect.maxX - 1.6, y: rect.maxY - 1.6))
        bevels.lineWidth = 1.1
        bevels.stroke()
    }

    /// A filled dot with an exclamation mark knocked out, cut clear of the keycap corner it overlaps.
    private static func drawBadge(at center: CGPoint) {
        let radius = 4.2
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: CGRect(x: center.x - radius - 1.2, y: center.y - radius - 1.2,
                                    width: 2 * (radius + 1.2), height: 2 * (radius + 1.2))).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.set()
        NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)).fill()
        NSGraphicsContext.current?.compositingOperation = .clear
        let stem = NSBezierPath()
        stem.move(to: CGPoint(x: center.x, y: center.y - 2.4))
        stem.line(to: CGPoint(x: center.x, y: center.y + 0.4))
        stem.lineWidth = 1.3
        stem.lineCapStyle = .round
        stem.stroke()
        NSBezierPath(ovalIn: CGRect(x: center.x - 0.7, y: center.y + 1.5, width: 1.4, height: 1.4)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    private static func drawWaves(from center: CGPoint) {
        NSColor.black.set()
        for radius in [2.6, 5.4] {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: CGPoint(x: center.x - 1.5, y: center.y), radius: radius, startAngle: -50, endAngle: 50)
            arc.lineWidth = 1.4
            arc.lineCapStyle = .round
            arc.stroke()
        }
    }

    private static func drawSlash(in rect: CGRect) {
        let slash = NSBezierPath()
        slash.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 1))
        slash.line(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 1))
        slash.lineCapStyle = .round
        NSGraphicsContext.current?.compositingOperation = .clear
        slash.lineWidth = 4
        slash.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.set()
        slash.lineWidth = 1.4
        slash.stroke()
    }
}
