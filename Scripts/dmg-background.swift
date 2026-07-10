// Draws the DMG window background: gradient + arrow between the app and the
// Applications drop target, plus a one-line hint. Output is 2x pixels at 144 DPI
// so Finder renders it at 640x400 points, crisp on Retina.
// Usage: swift Scripts/dmg-background.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"
let W = 1280, H = 800   // 2x of a 640x400-point window

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let full = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [NSColor(white: 0.98, alpha: 1), NSColor(white: 0.90, alpha: 1)])!
    .draw(in: full, angle: -90)

// Arrow between the two icon centers (points {160,205} and {480,205} -> 2x px,
// y flipped for bottom-left origin). Icons are 128pt wide, so leave a gap.
let y: CGFloat = CGFloat(H) - 410           // 205pt from top, in px
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 470, y: y))
arrow.line(to: NSPoint(x: 810, y: y))
arrow.lineWidth = 10
NSColor(white: 0.55, alpha: 1).setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 810, y: y))
head.line(to: NSPoint(x: 770, y: y + 26))
head.line(to: NSPoint(x: 770, y: y - 26))
head.close()
NSColor(white: 0.55, alpha: 1).setFill()
head.fill()

let hint = "Drag Junction into Applications" as NSString
let style = NSMutableParagraphStyle(); style.alignment = .center
hint.draw(in: NSRect(x: 0, y: CGFloat(H) - 150, width: CGFloat(W), height: 60),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .medium),
        .foregroundColor: NSColor(white: 0.35, alpha: 1),
        .paragraphStyle: style,
    ])

NSGraphicsContext.restoreGraphicsState()

// 144 DPI so 1280x800 px == 640x400 pt (matches the AppleScript window bounds).
rep.size = NSSize(width: 640, height: 400)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
