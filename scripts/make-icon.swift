// Generates the app icon set and menu bar template icon.
// Run via scripts/make-icon.sh — outputs into Assets/.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets"

/// Friendly bot head: antenna, rounded head, punched-out eyes and mouth.
/// Rendered into its own layer so the punches only cut the bot, not the
/// background it's later composited onto.
func drawSparkles(size: CGFloat, color: NSColor) {
    let bot = NSImage(size: NSSize(width: size, height: size))
    bot.lockFocus()
    drawBotShapes(size: size, color: color)
    bot.unlockFocus()
    bot.draw(in: CGRect(x: 0, y: 0, width: size, height: size),
             from: .zero, operation: .sourceOver, fraction: 1)
}

func drawBotShapes(size: CGFloat, color: NSColor) {
    let s = size
    color.setFill()

    // Antenna: ball + stem.
    NSBezierPath(ovalIn: CGRect(x: s * 0.455, y: s * 0.76, width: s * 0.09, height: s * 0.09)).fill()
    NSBezierPath(
        roundedRect: CGRect(x: s * 0.485, y: s * 0.66, width: s * 0.03, height: s * 0.12),
        xRadius: s * 0.015, yRadius: s * 0.015).fill()

    // Head.
    NSBezierPath(
        roundedRect: CGRect(x: s * 0.20, y: s * 0.18, width: s * 0.60, height: s * 0.50),
        xRadius: s * 0.13, yRadius: s * 0.13).fill()

    // Punch out eyes and mouth.
    NSGraphicsContext.current!.compositingOperation = .destinationOut
    let eye = s * 0.115
    NSBezierPath(ovalIn: CGRect(x: s * 0.315, y: s * 0.435, width: eye, height: eye)).fill()
    NSBezierPath(ovalIn: CGRect(x: s * 0.57, y: s * 0.435, width: eye, height: eye)).fill()
    NSBezierPath(
        roundedRect: CGRect(x: s * 0.375, y: s * 0.27, width: s * 0.25, height: s * 0.055),
        xRadius: s * 0.0275, yRadius: s * 0.0275).fill()
    NSGraphicsContext.current!.compositingOperation = .sourceOver
}

func drawAppIcon(size: CGFloat) {
    // macOS icon grid: content shape inset ~10%, corner radius ~22.4%.
    let inset = size * 0.098
    let shape = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = shape.width * 0.224
    let rounded = NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.93, green: 0.56, blue: 0.42, alpha: 1),   // #ED8F6B
        ending: NSColor(srgbRed: 0.72, green: 0.35, blue: 0.18, alpha: 1))!    // #B85A2E
    gradient.draw(in: rounded, angle: -60)

    drawSparkles(size: size, color: .white)
}

func renderPNG(pixels: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(pixels))
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "\(outDir)/AppIcon.iconset"
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let suffix = scale == 2 ? "@2x" : ""
        let data = renderPNG(pixels: pixels) { drawAppIcon(size: $0) }
        try! data.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(suffix).png"))
    }
}

// Menu bar template icon: black sparkles on transparent, 18 pt @2x.
let menuBar = renderPNG(pixels: 36) { drawSparkles(size: $0, color: .black) }
try! menuBar.write(to: URL(fileURLWithPath: "\(outDir)/MenuBarIcon.png"))

print("Wrote \(iconset) and \(outDir)/MenuBarIcon.png")
