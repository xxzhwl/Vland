import AppKit
import CoreGraphics
import Foundation

struct IconSpec {
    let fileName: String
    let pixelSize: Int
}

let specs: [IconSpec] = [
    .init(fileName: "Vland_16.png", pixelSize: 16),
    .init(fileName: "Vland_32.png", pixelSize: 32),
    .init(fileName: "Vland_32_1x.png", pixelSize: 32),
    .init(fileName: "Vland_64.png", pixelSize: 64),
    .init(fileName: "Vland_128.png", pixelSize: 128),
    .init(fileName: "Vland_256.png", pixelSize: 256),
    .init(fileName: "Vland_256_1x.png", pixelSize: 256),
    .init(fileName: "Vland_512.png", pixelSize: 512),
    .init(fileName: "Vland_512_1x.png", pixelSize: 512),
    .init(fileName: "Vland_1024.png", pixelSize: 1024),
]

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift generate_vland_icon.swift <appiconset-path>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255.0
    let green = CGFloat((hex >> 8) & 0xff) / 255.0
    let blue = CGFloat(hex & 0xff) / 255.0
    return CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func drawGradient(
    in context: CGContext,
    colors: [CGColor],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint
) {
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
        return
    }
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

func drawRadialGradient(
    in context: CGContext,
    colors: [CGColor],
    locations: [CGFloat],
    center: CGPoint,
    radius: CGFloat
) {
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
        return
    }
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
}

func withSavedState(_ context: CGContext, _ work: () -> Void) {
    context.saveGState()
    work()
    context.restoreGState()
}

func drawBaseIcon(in context: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let cardRect = canvas.insetBy(dx: 52, dy: 52)
    let cardPath = CGPath(
        roundedRect: cardRect,
        cornerWidth: 226,
        cornerHeight: 226,
        transform: nil
    )

    withSavedState(context) {
        context.addPath(cardPath)
        context.clip()

        drawGradient(
            in: context,
            colors: [color(0x080b12), color(0x111a26), color(0x070a10)],
            locations: [0.0, 0.56, 1.0],
            start: CGPoint(x: 120, y: 970),
            end: CGPoint(x: 910, y: 70)
        )

        drawRadialGradient(
            in: context,
            colors: [color(0x5ee0ff, alpha: 0.42), color(0x5ee0ff, alpha: 0.0)],
            locations: [0.0, 1.0],
            center: CGPoint(x: 300, y: 830),
            radius: 520
        )

        drawRadialGradient(
            in: context,
            colors: [color(0x27a4ff, alpha: 0.25), color(0x27a4ff, alpha: 0.0)],
            locations: [0.0, 1.0],
            center: CGPoint(x: 780, y: 180),
            radius: 360
        )
    }

    withSavedState(context) {
        context.setStrokeColor(color(0xffffff, alpha: 0.14))
        context.setLineWidth(10)
        context.addPath(cardPath)
        context.strokePath()
    }

    let pillRect = CGRect(x: 328, y: 782, width: 368, height: 82)
    let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 41, cornerHeight: 41, transform: nil)

    withSavedState(context) {
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: color(0x000000, alpha: 0.45))
        context.addPath(pillPath)
        context.setFillColor(color(0x05070b, alpha: 0.95))
        context.fillPath()
    }

    withSavedState(context) {
        context.addPath(pillPath)
        context.clip()
        drawGradient(
            in: context,
            colors: [color(0xffffff, alpha: 0.12), color(0xffffff, alpha: 0.01)],
            locations: [0.0, 1.0],
            start: CGPoint(x: pillRect.midX, y: pillRect.maxY),
            end: CGPoint(x: pillRect.midX, y: pillRect.minY)
        )
    }

    let markPath = CGMutablePath()
    markPath.move(to: CGPoint(x: 316, y: 702))
    markPath.addLine(to: CGPoint(x: 512, y: 254))
    markPath.addLine(to: CGPoint(x: 708, y: 702))

    withSavedState(context) {
        context.setLineWidth(158)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShadow(offset: CGSize(width: 0, height: -16), blur: 56, color: color(0x02050a, alpha: 0.72))
        context.addPath(markPath)
        context.setStrokeColor(color(0x021018, alpha: 0.82))
        context.strokePath()
    }

    withSavedState(context) {
        let stroked = markPath.copy(
            strokingWithWidth: 132,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10,
            transform: .identity
        )
        context.addPath(stroked)
        context.clip()

        drawGradient(
            in: context,
            colors: [color(0xffffff), color(0xa2f1ff), color(0x3bd4ff)],
            locations: [0.0, 0.52, 1.0],
            start: CGPoint(x: 360, y: 760),
            end: CGPoint(x: 690, y: 220)
        )

        drawRadialGradient(
            in: context,
            colors: [color(0xffffff, alpha: 0.36), color(0xffffff, alpha: 0.0)],
            locations: [0.0, 1.0],
            center: CGPoint(x: 430, y: 665),
            radius: 200
        )
    }

    withSavedState(context) {
        context.setLineWidth(34)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(markPath)
        context.setStrokeColor(color(0xffffff, alpha: 0.28))
        context.strokePath()
    }
}

func render(spec: IconSpec) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: spec.pixelSize,
        pixelsHigh: spec.pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "VlandIcon", code: 1)
    }

    bitmap.size = NSSize(width: spec.pixelSize, height: spec.pixelSize)

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
        throw NSError(domain: "VlandIcon", code: 2)
    }

    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(spec.pixelSize) / 1024.0, y: CGFloat(spec.pixelSize) / 1024.0)
    drawBaseIcon(in: context)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VlandIcon", code: 3)
    }

    try data.write(to: outputDirectory.appendingPathComponent(spec.fileName))
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for spec in specs {
    try render(spec: spec)
}

print("Generated \(specs.count) Vland icon assets in \(outputDirectory.path)")
