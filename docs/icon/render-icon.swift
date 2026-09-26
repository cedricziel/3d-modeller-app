import AppKit

let size: CGFloat = 1024
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(squircle)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 0.20, green: 0.52, blue: 1.0, alpha: 1).cgColor,
        NSColor(srgbRed: 0.33, green: 0.20, blue: 0.78, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(
    background, start: CGPoint(x: body.minX, y: body.maxY),
    end: CGPoint(x: body.maxX, y: body.minY), options: [])

let c = CGPoint(x: 512, y: 470)
let r: CGFloat = 250
let dx = r * cos(.pi / 6), dy = r * sin(.pi / 6)
let top = CGPoint(x: c.x, y: c.y + r)
let upperLeft = CGPoint(x: c.x - dx, y: c.y + dy)
let upperRight = CGPoint(x: c.x + dx, y: c.y + dy)
let lowerLeft = CGPoint(x: c.x - dx, y: c.y - dy)
let lowerRight = CGPoint(x: c.x + dx, y: c.y - dy)
let bottom = CGPoint(x: c.x, y: c.y - r)

func face(_ points: [CGPoint], _ white: CGFloat) {
    ctx.beginPath()
    ctx.addLines(between: points)
    ctx.closePath()
    ctx.setFillColor(NSColor(white: white, alpha: 1).cgColor)
    ctx.fillPath()
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
face([top, upperRight, c, upperLeft, top], 1.0)
ctx.restoreGState()
face([top, upperRight, c, upperLeft], 1.0)
face([upperLeft, c, bottom, lowerLeft], 0.86)
face([c, upperRight, lowerRight, bottom], 0.70)

ctx.setStrokeColor(NSColor(srgbRed: 0.27, green: 0.30, blue: 0.85, alpha: 0.35).cgColor)
ctx.setLineWidth(6)
ctx.setLineJoin(.round)
ctx.beginPath()
ctx.addLines(between: [top, upperRight, lowerRight, bottom, lowerLeft, upperLeft, top])
ctx.move(to: c); ctx.addLine(to: upperLeft)
ctx.move(to: c); ctx.addLine(to: upperRight)
ctx.move(to: c); ctx.addLine(to: bottom)
ctx.strokePath()

func sparkle(at p: CGPoint, radius s: CGFloat) {
    let w = s * 0.22
    ctx.beginPath()
    ctx.move(to: CGPoint(x: p.x, y: p.y + s))
    ctx.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: CGPoint(x: p.x + w, y: p.y + w))
    ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: CGPoint(x: p.x + w, y: p.y - w))
    ctx.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: CGPoint(x: p.x - w, y: p.y - w))
    ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: CGPoint(x: p.x - w, y: p.y + w))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
}
sparkle(at: CGPoint(x: 770, y: 770), radius: 78)
sparkle(at: CGPoint(x: 850, y: 640), radius: 36)
ctx.restoreGState()

NSGraphicsContext.current = nil
let out = CommandLine.arguments[1]
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
