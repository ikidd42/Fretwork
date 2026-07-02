import AppKit
import CoreGraphics

// Fretwork app icon: a fretboard seen straight on — six strings, frets,
// and a glowing 12th-fret inlay dot — on an indigo gradient, drawn inside
// the macOS icon grid (824pt content square centered in 1024, r≈185).

let canvas = 1024
let ctx = CGContext(
    data: nil, width: canvas, height: canvas,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

let content = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

// ── Background: vertical indigo gradient with soft edge shading ──
let bgPath = CGPath(roundedRect: content, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

let gradientColors = [
    CGColor(srgbRed: 0.290, green: 0.270, blue: 0.620, alpha: 1),  // top indigo
    CGColor(srgbRed: 0.130, green: 0.115, blue: 0.360, alpha: 1),  // bottom deep
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: gradientColors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 512, y: content.maxY),
                       end: CGPoint(x: 512, y: content.minY),
                       options: [])

// Subtle vignette to give the slab depth.
let vignette = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10),
                                   CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.0)] as CFArray,
                          locations: [0, 1])!
ctx.drawRadialGradient(vignette,
                       startCenter: CGPoint(x: 512, y: 700), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 700), endRadius: 700,
                       options: [])

// ── Frets: nut at the top, three slimmer frets below ──
// Fret spacing shrinks going up the neck (down the icon), like a real board.
let nutY: CGFloat = 795
let fretYs: [CGFloat] = [600, 425, 265]
let fretInset: CGFloat = 190

let nutRect = CGRect(x: fretInset, y: nutY - 15, width: 1024 - fretInset * 2, height: 30)
ctx.addPath(CGPath(roundedRect: nutRect, cornerWidth: 15, cornerHeight: 15, transform: nil))
ctx.setFillColor(CGColor(srgbRed: 0.90, green: 0.90, blue: 0.94, alpha: 0.95))
ctx.fillPath()

for y in fretYs {
    let rect = CGRect(x: fretInset, y: y - 6, width: 1024 - fretInset * 2, height: 12)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0.88, green: 0.89, blue: 0.94, alpha: 0.30))
    ctx.fillPath()
}

// ── Strings: six verticals, thick (wound) to thin (plain) ──
let stringXs: [CGFloat] = [268, 365.6, 463.2, 560.8, 658.4, 756]
let stringWidths: [CGFloat] = [21, 18, 15, 11, 8, 6]
for (i, x) in stringXs.enumerated() {
    let w = stringWidths[i]
    // Soft shadow line behind each string for depth.
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
    ctx.fill(CGRect(x: x - w / 2 + 4, y: 100, width: w, height: 824))
    ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.92, blue: 0.88, alpha: 0.92))
    ctx.fill(CGRect(x: x - w / 2, y: 100, width: w, height: 824))
}

// ── 12th-fret inlay: glowing dot as the focal point (drawn over strings) ──
let inlayCenter = CGPoint(x: 512, y: (fretYs[0] + fretYs[1]) / 2)
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      colors: [CGColor(srgbRed: 1.0, green: 0.98, blue: 0.88, alpha: 0.65),
                               CGColor(srgbRed: 1.0, green: 0.98, blue: 0.88, alpha: 0.0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: inlayCenter, startRadius: 0,
                       endCenter: inlayCenter, endRadius: 150,
                       options: [])
ctx.setFillColor(CGColor(srgbRed: 0.98, green: 0.97, blue: 0.90, alpha: 0.97))
ctx.fillEllipse(in: CGRect(x: inlayCenter.x - 50, y: inlayCenter.y - 50, width: 100, height: 100))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
