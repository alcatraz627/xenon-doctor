// Draws the app icon: a rounded green-to-teal tile, a white game controller, and a small
// yellow first-aid cross for the "doctor" part. Writes a 1024 px PNG to the path given.
//
// Build and run through tools/makeicon.sh, which also turns the PNG into AppIcon.icns.
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let tile = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.21, yRadius: size * 0.21)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.47, alpha: 1),
                              ending: NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.38, alpha: 1))!
    gradient.draw(in: tile, angle: -65)

    // Soft highlight across the top so the tile reads as glass rather than flat paint.
    NSGraphicsContext.current?.saveGraphicsState()
    tile.addClip()
    let gloss = NSGradient(starting: NSColor.white.withAlphaComponent(0.18), ending: NSColor.white.withAlphaComponent(0))!
    gloss.draw(in: NSRect(x: 0, y: size * 0.55, width: size, height: size * 0.45), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let padCfg = NSImage.SymbolConfiguration(pointSize: size * 0.50, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let pad = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?.withSymbolConfiguration(padCfg) {
        let s = pad.size
        let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2 + size * 0.03)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = size * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.set()
        pad.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // First-aid cross, bottom right, on a white disc.
    let disc = NSRect(x: size * 0.64, y: size * 0.16, width: size * 0.22, height: size * 0.22)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: disc).fill()
    let crossCfg = NSImage.SymbolConfiguration(pointSize: size * 0.13, weight: .bold)
        .applying(.init(paletteColors: [NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.14, alpha: 1)]))
    if let cross = NSImage(systemSymbolName: "cross.fill", accessibilityDescription: nil)?.withSymbolConfiguration(crossCfg) {
        let s = cross.size
        cross.draw(at: NSPoint(x: disc.midX - s.width / 2, y: disc.midY - s.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
    }
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("could not render icon\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out) \(Int(rep.pixelsWide))x\(Int(rep.pixelsHigh))")
} catch {
    fputs("write failed: \(error)\n", stderr)
    exit(1)
}
