// Generates the app icon set and menu bar template icon.
// Run via scripts/make-icon.sh — outputs into Assets/.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets"

/// Eight-ray asterisk burst — Claude-flavored, geometric rather than a copy
/// of the actual trademark. Rays are round-capped capsules from the center.
func drawSparkles(size: CGFloat, color: NSColor) {
    color.setFill()
    let center = CGPoint(x: size * 0.5, y: size * 0.5)
    let outer = size * 0.315
    let width = size * 0.105
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4
        let ray = NSBezierPath(
            roundedRect: CGRect(x: 0, y: -width / 2, width: outer, height: width),
            xRadius: width / 2, yRadius: width / 2)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: angle)
        ray.transform(using: transform as AffineTransform)
        ray.fill()
    }
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
