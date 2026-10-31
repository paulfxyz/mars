import AppKit

let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let rect = NSRect(origin: .zero, size: size)
let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 210, yRadius: 210)
NSColor(red: 0.13, green: 0.15, blue: 0.15, alpha: 1).setFill()
rounded.fill()
NSGradient(starting: NSColor(red: 0.87, green: 0.31, blue: 0.21, alpha: 1),
           ending: NSColor(red: 0.61, green: 0.13, blue: 0.10, alpha: 1))!.draw(in: rounded, angle: -60)
let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 819))
shield.curve(to: NSPoint(x: 780, y: 705), controlPoint1: NSPoint(x: 610, y: 755), controlPoint2: NSPoint(x: 710, y: 731))
shield.line(to: NSPoint(x: 760, y: 480))
shield.curve(to: NSPoint(x: 512, y: 203), controlPoint1: NSPoint(x: 746, y: 350), controlPoint2: NSPoint(x: 610, y: 250))
shield.curve(to: NSPoint(x: 264, y: 480), controlPoint1: NSPoint(x: 414, y: 250), controlPoint2: NSPoint(x: 278, y: 350))
shield.line(to: NSPoint(x: 244, y: 705))
shield.curve(to: NSPoint(x: 512, y: 819), controlPoint1: NSPoint(x: 314, y: 731), controlPoint2: NSPoint(x: 414, y: 755))
shield.close()
NSColor(red: 0.98, green: 0.92, blue: 0.78, alpha: 1).setFill()
shield.fill()
NSColor(red: 0.13, green: 0.27, blue: 0.25, alpha: 1).setStroke()
// Original fan/clam motif, echoing the guardian's shield, not ClamAV's logo.
for i in 0..<7 {
    let angle = Double(i) * Double.pi / 8 + Double.pi / 8
    let endpoint = NSPoint(x: 512 + cos(angle) * 182, y: 464 + sin(angle) * 196)
    let rib = NSBezierPath()
    rib.move(to: NSPoint(x: 512, y: 385))
    rib.curve(to: endpoint, controlPoint1: NSPoint(x: endpoint.x, y: 491), controlPoint2: NSPoint(x: endpoint.x, y: endpoint.y - 18))
    rib.lineWidth = 28; rib.lineCapStyle = .round; rib.stroke()
}
let base = NSBezierPath()
base.move(to: NSPoint(x: 464, y: 354)); base.line(to: NSPoint(x: 560, y: 354))
base.lineWidth = 24; base.lineCapStyle = .round; base.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
