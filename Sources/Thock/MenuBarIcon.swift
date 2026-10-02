import AppKit

/// Menu bar icon proposals. The shipping icon stays `AppModel.menuBarSymbol` unless the hidden
/// `menuBarIcon` default names a style, e.g. `defaults write io.github.dailyxplorer.thock menuBarIcon keycap`.
enum MenuBarIcon {
    enum State: CaseIterable {
        case on
        case off
        case muted
        case attention
    }

    enum Style: String, CaseIterable {
        case keycap
        case keycapWaves
        case waveform

        static var selected: Style? {
            UserDefaults.standard.string(forKey: "menuBarIcon").flatMap(Style.init(rawValue:))
        }

        var title: String {
            switch self {
            case .keycap: "Keycap"
            case .keycapWaves: "Keycap + Sound"
            case .waveform: "Waveform"
            }
        }
    }

    static func image(_ style: Style, _ state: State) -> NSImage {
        let size = NSSize(width: style == .keycapWaves ? 22 : 18, height: 16)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Template alpha survives in the menu bar, so an automatic mute reads as a dimmed icon, unlike the slashed manual off.
            context.setAlpha(state == .muted ? 0.45 : 1)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            switch style {
            case .keycap: drawKeycap(in: CGRect(x: 1, y: 1, width: 16, height: 14), state: state)
            case .keycapWaves:
                drawKeycap(in: CGRect(x: 1, y: 2, width: 13, height: 12), state: state)
                if state != .attention { drawWaves(from: CGPoint(x: 15.5, y: 8)) }
            case .waveform: drawSymbol(state == .attention ? "waveform.badge.exclamationmark" : "waveform", in: rect)
            }
            if state == .off { drawSlash(in: rect) }
            context.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Thock"
        return image
    }

    private static func drawKeycap(in rect: CGRect, state: State) {
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
        if state == .attention {
            for index in 0..<3 {
                let x = face.midX + CGFloat(index - 1) * 2.6
                NSBezierPath(ovalIn: CGRect(x: x - 0.8, y: face.midY - 0.8, width: 1.6, height: 1.6)).fill()
            }
        }
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

    private static func drawSymbol(_ name: String, in rect: CGRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let origin = CGPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)
        symbol.draw(in: CGRect(origin: origin, size: symbol.size))
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
