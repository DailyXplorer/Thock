import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let catalog = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/Thock/Resources/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ context: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, _ rect: CGRect) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom, top] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    context.restoreGState()
}

func draw(_ context: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(roundedRect(tile, 185))
    context.setFillColor(color(0x1B1D2A))
    context.fillPath()
    context.restoreGState()
    fillGradient(context, roundedRect(tile, 185), color(0x34364F), color(0x15161F), tile)

    let skirt = CGRect(x: 214, y: 286, width: 400, height: 400)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: color(0x000000, 0.45))
    context.addPath(roundedRect(skirt, 78))
    context.setFillColor(color(0xB59F80))
    context.fillPath()
    context.restoreGState()
    fillGradient(context, roundedRect(skirt, 78), color(0xCDB896), color(0x9C8566), skirt)

    let top = CGRect(x: 254, y: 350, width: 320, height: 300)
    fillGradient(context, roundedRect(top, 56), color(0xFFF8EB), color(0xE6D6BA), top)
    let dish = top.insetBy(dx: 46, dy: 52)
    context.saveGState()
    context.addEllipse(in: dish)
    context.clip()
    let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xD9C7A8, 0.55), color(0xD9C7A8, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(shade, startCenter: CGPoint(x: dish.midX, y: dish.midY + 20), startRadius: 0,
                               endCenter: CGPoint(x: dish.midX, y: dish.midY), endRadius: dish.width / 2, options: [])
    context.restoreGState()

    context.setLineCap(.round)
    context.setLineWidth(38)
    let center = CGPoint(x: 600, y: 486)
    for (index, radius) in [CGFloat(110), 190, 270].enumerated() {
        context.setStrokeColor(color(0xFF8A3D, 1 - CGFloat(index) * 0.28))
        context.addArc(center: center, radius: radius, startAngle: -.pi / 4.2, endAngle: .pi / 4.2, clockwise: false)
        context.strokePath()
    }
}

func png(size: Int) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(context)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return strippingMetadata(data as Data)
}

func strippingMetadata(_ png: Data) -> Data {
    let metadataChunks: Set<String> = ["eXIf", "tEXt", "iTXt", "zTXt", "tIME"]
    let bytes = [UInt8](png)
    var output = Data(bytes.prefix(8))
    var offset = 8
    while offset + 12 <= bytes.count {
        let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        let end = offset + 12 + length
        if !metadataChunks.contains(String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)) {
            output.append(contentsOf: bytes[offset..<end])
        }
        offset = end
    }
    return output
}

func writeIfChanged(_ data: Data, to url: URL) throws {
    if (try? Data(contentsOf: url)) != data {
        try data.write(to: url)
        print("wrote \(url.lastPathComponent)")
    }
}

let slots: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [String] = []
var expected: Set<String> = ["Contents.json"]
for pixels in Set(slots.map { $0.points * $0.scale }).sorted() {
    let name = "icon_\(pixels).png"
    expected.insert(name)
    try writeIfChanged(png(size: pixels), to: iconSet.appendingPathComponent(name))
}
for slot in slots {
    images.append("""
        { "filename" : "icon_\(slot.points * slot.scale).png", "idiom" : "mac", "scale" : "\(slot.scale)x", "size" : "\(slot.points)x\(slot.points)" }
    """)
}
let contents = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try writeIfChanged(Data(contents.utf8), to: iconSet.appendingPathComponent("Contents.json"))
try writeIfChanged(Data("{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n".utf8), to: catalog.appendingPathComponent("Contents.json"))
for stale in try FileManager.default.contentsOfDirectory(atPath: iconSet.path) where !expected.contains(stale) {
    try FileManager.default.removeItem(at: iconSet.appendingPathComponent(stale))
    print("removed \(stale)")
}
