import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: ~824pt rounded square centred in 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(tilePath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.27, alpha: 1).cgColor,
                             NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.10, alpha: 1).cgColor] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// rainbow underglow
let hues: [CGFloat] = [0.0, 0.08, 0.16, 0.33, 0.5, 0.62, 0.75, 0.88]
for (i, h) in hues.enumerated() {
    let x = 250 + CGFloat(i) * 75
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(calibratedHue: h, saturation: 0.9, brightness: 1, alpha: 0.55).cgColor,
                                   NSColor(calibratedHue: h, saturation: 0.9, brightness: 1, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: 330), startRadius: 0,
                           endCenter: CGPoint(x: x, y: 330), endRadius: 170, options: [])
}

// white keycap glow
let capGlow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [NSColor.white.withAlphaComponent(0.45).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                         locations: [0, 1])!
ctx.drawRadialGradient(capGlow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 380, options: [])

// keycap: skirt then top
let skirt = CGRect(x: 302, y: 360, width: 420, height: 400)
ctx.addPath(CGPath(roundedRect: skirt, cornerWidth: 70, cornerHeight: 70, transform: nil))
ctx.setFillColor(NSColor(calibratedWhite: 0.80, alpha: 1).cgColor); ctx.fillPath()
let top = CGRect(x: 352, y: 430, width: 320, height: 300)
let topPath = CGPath(roundedRect: top, cornerWidth: 50, cornerHeight: 50, transform: nil)
ctx.saveGState()
ctx.addPath(topPath); ctx.clip()
let topGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                         colors: [NSColor.white.cgColor, NSColor(calibratedWhite: 0.90, alpha: 1).cgColor] as CFArray,
                         locations: [0, 1])!
ctx.drawLinearGradient(topGrad, start: CGPoint(x: 512, y: 730), end: CGPoint(x: 512, y: 430), options: [])
ctx.restoreGState()

// legend
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 190, weight: .heavy),
    .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.19, alpha: 1),
    .paragraphStyle: para,
]
("Y" as NSString).draw(in: CGRect(x: 352, y: 460, width: 320, height: 240), withAttributes: attrs)
ctx.restoreGState()
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
