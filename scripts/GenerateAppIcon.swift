import AppKit
import Foundation

// Deterministic original icon; no downloaded assets or font redistribution.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon bitmap unavailable") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.075, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(calibratedRed: 0.07, green: 0.18, blue: 0.22, alpha: 1).setStroke()
for n in stride(from: 128, through: 896, by: 128) {
    let path = NSBezierPath(); path.lineWidth = 3
    path.move(to: NSPoint(x: CGFloat(n), y: 80)); path.line(to: NSPoint(x: CGFloat(n), y: 944))
    path.move(to: NSPoint(x: 80, y: CGFloat(n))); path.line(to: NSPoint(x: 944, y: CGFloat(n))); path.stroke()
}
let diamond = NSBezierPath()
diamond.move(to: NSPoint(x: 512, y: 900)); diamond.line(to: NSPoint(x: 900, y: 512))
diamond.line(to: NSPoint(x: 512, y: 124)); diamond.line(to: NSPoint(x: 124, y: 512)); diamond.close()
diamond.lineWidth = 22
NSColor(calibratedRed: 0.20, green: 0.88, blue: 0.82, alpha: 1).setStroke(); diamond.stroke()
let text = "W" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 340, weight: .black), .foregroundColor: NSColor.white]
let size = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (1024-size.width)/2, y: (1024-size.height)/2+20), withAttributes: attributes)
NSColor(calibratedRed: 1, green: 0.67, blue: 0.22, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 476, y: 182, width: 72, height: 72)).fill()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: directory.appendingPathComponent("AppIcon.png"))
let catalog = "{\"images\":[{\"filename\":\"AppIcon.png\",\"idiom\":\"universal\",\"platform\":\"ios\",\"size\":\"1024x1024\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}"
try catalog.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: directory.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Generated original opaque 1024x1024 WORLD.EXE icon.")
