import AppKit
// Draws the DMG window background at 1x and 2x: make_bg <out1x.png> <out2x.png>
func draw(scale: CGFloat, to path: String) {
    let w = 640 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.23, alpha: 1).cgColor,
                                 NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.11, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 400), end: CGPoint(x: 0, y: 0), options: [])
    // rainbow strip along the bottom
    let hues: [CGFloat] = [0.0, 0.08, 0.16, 0.33, 0.5, 0.62, 0.75, 0.88]
    for (i, hue) in hues.enumerated() {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor(calibratedHue: hue, saturation: 0.9, brightness: 1, alpha: 0.35).cgColor,
                                    NSColor(calibratedHue: hue, saturation: 0.9, brightness: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        let x = 40 + CGFloat(i) * 80
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: -10), startRadius: 0, endCenter: CGPoint(x: x, y: -10), endRadius: 120, options: [])
    }
    let para = NSMutableParagraphStyle(); para.alignment = .center
    ("Yunzii Control" as NSString).draw(in: CGRect(x: 0, y: 320, width: 640, height: 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: para])
    ("Drag the app into Applications to install" as NSString).draw(in: CGRect(x: 0, y: 70, width: 640, height: 24), withAttributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.75), .paragraphStyle: para])
    // arrow between the two icons (icons sit at x=170 and x=470, y=200 from top)
    let y: CGFloat = 400 - 200
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 262, y: y)); arrow.line(to: CGPoint(x: 368, y: y))
    arrow.lineWidth = 6; arrow.lineCapStyle = .round
    NSColor(white: 1, alpha: 0.85).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 352, y: y + 16)); head.line(to: CGPoint(x: 374, y: y)); head.line(to: CGPoint(x: 352, y: y - 16))
    head.lineWidth = 6; head.lineCapStyle = .round; head.lineJoinStyle = .round; head.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
draw(scale: 1, to: CommandLine.arguments[1])
draw(scale: 2, to: CommandLine.arguments[2])
