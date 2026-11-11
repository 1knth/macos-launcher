// Renders Resources/Prism.png: a light-splitting prism on a dark squircle.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let inset = 100.0
let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.15, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.05, green: 0.05, blue: 0.09, alpha: 1)])!.draw(in: tile, angle: -90)
let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
for (index, color) in colors.enumerated() {
    let beam = NSBezierPath()
    let y = 560.0 - Double(index) * 34
    beam.move(to: NSPoint(x: 560, y: 520))
    beam.line(to: NSPoint(x: 860, y: y + 34))
    beam.line(to: NSPoint(x: 860, y: y))
    beam.close()
    color.withAlphaComponent(0.92).setFill()
    beam.fill()
}
let light = NSBezierPath()
light.move(to: NSPoint(x: 160, y: 470))
light.line(to: NSPoint(x: 470, y: 520))
light.line(to: NSPoint(x: 470, y: 535))
light.line(to: NSPoint(x: 160, y: 490))
light.close()
NSColor.white.withAlphaComponent(0.9).setFill()
light.fill()
let prism = NSBezierPath()
prism.move(to: NSPoint(x: 512, y: 780))
prism.line(to: NSPoint(x: 290, y: 300))
prism.line(to: NSPoint(x: 734, y: 300))
prism.close()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0.18)])!.draw(in: prism, angle: -60)
NSColor.white.withAlphaComponent(0.85).setStroke()
prism.lineWidth = 14
prism.lineJoinStyle = .round
prism.stroke()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
