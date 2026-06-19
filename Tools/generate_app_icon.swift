import AppKit
import CoreGraphics

// LumenFocus app-icon generator.
// Concept: a minimalist eye (almond lens) with a glowing iris ring + pupil on
// a deep-black squircle — "eye-care" + "lumen / focus". Pure black & white.
//
// Regenerate the full appiconset:
//   swift Tools/generate_app_icon.swift \
//     LumenFocus/LumenFocus/Assets.xcassets/AppIcon.appiconset
//   # then: for f in eye_*.png; do mv "$f" "icon_${f#eye_}"; done
//
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func render(_ S: CGFloat) -> CGImage {
    let px = Int(S)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    let side = S * 0.84
    let origin = (S - side) / 2.0
    let rect = CGRect(x: origin, y: origin, width: side, height: side)
    let radius = side * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let cx = S / 2.0, cy = S / 2.0

    // Shadow + black base
    ctx.saveGState()
    if S >= 64 {
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
    }
    ctx.addPath(squircle); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Gradient + glow
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [
        NSColor(white: 0.12, alpha: 1).cgColor, NSColor(white: 0.0, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: cx, y: rect.maxY), end: CGPoint(x: cx, y: rect.minY), options: [])
    let glow = CGGradient(colorsSpace: cs, colors: [
        NSColor(white: 1, alpha: 0.20).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: side * 0.46, options: [])
    ctx.restoreGState()

    // --- Eye almond (vesica) outline ---
    let w = side * 0.66
    let h = side * 0.42
    let L = CGPoint(x: cx - w/2, y: cy)
    let R = CGPoint(x: cx + w/2, y: cy)
    let eye = CGMutablePath()
    eye.move(to: L)
    eye.addCurve(to: R, control1: CGPoint(x: cx - w*0.42, y: cy + h*0.72),
                       control2: CGPoint(x: cx + w*0.42, y: cy + h*0.72))
    eye.addCurve(to: L, control1: CGPoint(x: cx + w*0.42, y: cy - h*0.72),
                       control2: CGPoint(x: cx - w*0.42, y: cy - h*0.72))
    eye.closeSubpath()
    ctx.addPath(eye)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(side * 0.046)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Iris ring
    let ringD = side * 0.255
    ctx.setLineWidth(side * 0.040)
    ctx.strokeEllipse(in: CGRect(x: cx - ringD/2, y: cy - ringD/2, width: ringD, height: ringD))
    // Pupil dot
    let dotD = side * 0.095
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: cx - dotD/2, y: cy - dotD/2, width: dotD, height: dotD))

    return ctx.makeImage()!
}

for s in sizes {
    let img = render(CGFloat(s))
    let rep = NSBitmapImageRep(cgImage: img); rep.size = NSSize(width: s, height: s)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/eye_\(s).png"))
}
print("done")
