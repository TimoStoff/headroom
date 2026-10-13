// Renders the README banner into docs/banner.png: app icon, name, tagline and a sample menu bar strip.
// Usage: swift scripts/make-banner.swift
import AppKit

let scale: CGFloat = 2
let size = NSSize(width: 1280, height: 320)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(origin: .zero, size: size)
let card = NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28)
card.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1),
                    NSColor(srgbRed: 0.15, green: 0.16, blue: 0.21, alpha: 1)])!.draw(in: bounds, angle: 20)

let white = NSColor.white
let secondary = NSColor(white: 1, alpha: 0.62)

if let icon = NSImage(contentsOf: URL(fileURLWithPath: "Resources/AppIcon.icns")) {
    icon.draw(in: NSRect(x: 56, y: 60, width: 200, height: 200))
}

func text(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
}

text("Headroom", .systemFont(ofSize: 76, weight: .bold), white).draw(at: NSPoint(x: 286, y: 158))
text("How much headroom is left, on your Mac and your AI coding plans.",
     .systemFont(ofSize: 25, weight: .regular), secondary).draw(at: NSPoint(x: 290, y: 114))

// A sample menu bar strip, drawn the way the app draws it.
let barFont = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
let symbolConfig = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
func symbol(_ name: String) -> NSImage? {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) else { return nil }
    let tinted = NSImage(size: img.size, flipped: false) { r in
        img.draw(in: r)
        white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    return tinted
}

let pillX: CGFloat = 290, padding: CGFloat = 20
let midY: CGFloat = 68
// Two passes: measure the strip, then draw the pill to fit and the strip on top.
var measuring = true
var x = pillX + padding
func drawSymbol(_ name: String) {
    guard let img = symbol(name) else { return }
    if !measuring { img.draw(in: NSRect(x: x, y: midY - img.size.height / 2, width: img.size.width, height: img.size.height)) }
    x += img.size.width + 6
}
func drawValue(_ s: String) {
    let t = text(s, barFont, white)
    if !measuring { t.draw(at: NSPoint(x: x, y: midY - t.size().height / 2)) }
    x += t.size().width + 26
}
func drawGauges(_ values: [CGFloat]) {
    if measuring { x += CGFloat(values.count) * 9 + 20; return }
    for v in values {
        let r = NSRect(x: x, y: midY - 14, width: 6, height: 28)
        NSColor(white: 1, alpha: 0.22).setFill()
        NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
        white.setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: 6, height: 28 * v), xRadius: 2, yRadius: 2).fill()
        x += 9
    }
    x += 20
}

func strip() {
    x = pillX + padding
    drawSymbol("cpu"); drawValue("29%")
    drawSymbol("memorychip"); drawValue("84%")
    drawSymbol("sparkle"); drawGauges([0.26, 0.47, 0.20])
    drawSymbol("bolt.horizontal.circle"); drawGauges([0.62])
    drawSymbol("cup.and.saucer.fill")
    x -= 6
}

strip()
NSColor(white: 1, alpha: 0.08).setFill()
NSBezierPath(roundedRect: NSRect(x: pillX, y: midY - 24, width: x + padding - pillX, height: 48), xRadius: 12, yRadius: 12).fill()
measuring = false
strip()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/banner.png"))
print("Wrote docs/banner.png")
