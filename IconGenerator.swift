import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let pixelSize = Int(CommandLine.arguments[1]),
      pixelSize > 0 else {
    fputs("Usage: IconGenerator <size> <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = CGFloat(pixelSize)
let scale = size / 1024

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create bitmap\n", stderr)
    exit(3)
}

bitmap.size = NSSize(width: size, height: size)
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create graphics context\n", stderr)
    exit(4)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: scale, y: scale)
context.cgContext.translateBy(x: 0, y: 1024)
context.cgContext.scaleBy(x: 1, y: -1)

let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.97, green: 0.78, blue: 0.45, alpha: 1),
    ending: NSColor(calibratedRed: 0.85, green: 0.36, blue: 0.12, alpha: 1)
)!
gradient.draw(in: background, angle: -45)

let white = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.91, alpha: 1)
let coffee = NSColor(calibratedRed: 0.34, green: 0.14, blue: 0.06, alpha: 1)

func stroke(_ path: NSBezierPath, width: CGFloat, color: NSColor = white) {
    color.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
}

let handle = NSBezierPath()
handle.appendArc(withCenter: NSPoint(x: 749, y: 616), radius: 91, startAngle: -76, endAngle: 76)
stroke(handle, width: 58)

let cup = NSBezierPath()
cup.move(to: NSPoint(x: 250, y: 550))
cup.line(to: NSPoint(x: 250, y: 634))
cup.curve(to: NSPoint(x: 465, y: 842), controlPoint1: NSPoint(x: 250, y: 754), controlPoint2: NSPoint(x: 345, y: 842))
cup.line(to: NSPoint(x: 530, y: 842))
cup.curve(to: NSPoint(x: 745, y: 634), controlPoint1: NSPoint(x: 650, y: 842), controlPoint2: NSPoint(x: 745, y: 754))
cup.line(to: NSPoint(x: 745, y: 550))
cup.close()
white.setFill()
cup.fill()

let coffeeSurface = NSBezierPath(ovalIn: NSRect(x: 250, y: 493, width: 495, height: 118))
white.setFill()
coffeeSurface.fill()
let innerCoffee = NSBezierPath(ovalIn: NSRect(x: 284, y: 516, width: 427, height: 72))
coffee.setFill()
innerCoffee.fill()

let saucer = NSBezierPath()
saucer.move(to: NSPoint(x: 205, y: 866))
saucer.line(to: NSPoint(x: 817, y: 866))
stroke(saucer, width: 38)

for (x, high) in [(354.0, false), (505.0, true), (654.0, false)] {
    let steam = NSBezierPath()
    let startY: CGFloat = high ? 450 : 445
    steam.move(to: NSPoint(x: x, y: startY))
    steam.curve(
        to: NSPoint(x: x, y: high ? 250 : 280),
        controlPoint1: NSPoint(x: x + 62, y: startY - 72),
        controlPoint2: NSPoint(x: x - 62, y: high ? 330 : 355)
    )
    stroke(steam, width: 42)
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG\n", stderr)
    exit(5)
}

do {
    try data.write(to: outputURL)
} catch {
    fputs("Could not write PNG: \(error)\n", stderr)
    exit(6)
}
