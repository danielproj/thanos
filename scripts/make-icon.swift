import AppKit
// Renders the app icon: a violet-to-amber squircle with a white sparkle glyph.
let out = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for s in sizes {
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let inset = r.insetBy(dx: r.width * 0.09, dy: r.height * 0.09)
        let path = NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.225, yRadius: inset.height * 0.225)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowBlurRadius = r.width * 0.03; shadow.shadowOffset = .init(width: 0, height: -r.width * 0.01)
        shadow.shadowColor = .black.withAlphaComponent(0.35); shadow.set()
        NSGradient(colors: [NSColor(red: 0.36, green: 0.16, blue: 0.85, alpha: 1), NSColor(red: 0.86, green: 0.25, blue: 0.62, alpha: 1), NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1)])!
            .draw(in: path, angle: -55)
        NSGraphicsContext.current?.restoreGraphicsState()
        NSGradient(colors: [.white.withAlphaComponent(0.35), .white.withAlphaComponent(0)])!.draw(in: NSBezierPath(roundedRect: NSRect(x: inset.minX, y: inset.midY, width: inset.width, height: inset.height / 2), xRadius: inset.width * 0.225, yRadius: inset.width * 0.225), angle: -90)
        let cfg = NSImage.SymbolConfiguration(pointSize: r.width * 0.42, weight: .semibold).applying(.init(paletteColors: [.white]))
        if let sym = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let sz = sym.size
            sym.draw(in: NSRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
        }
        return true
    }
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    if s <= 512 { try! png.write(to: URL(fileURLWithPath: "\(out)/icon_\(s)x\(s).png")) }
    if s >= 32 { try! png.write(to: URL(fileURLWithPath: "\(out)/icon_\(s/2)x\(s/2)@2x.png")) }
}
