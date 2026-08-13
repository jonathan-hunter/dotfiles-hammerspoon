// One-shot generator for the menu bar caffeine indicator.
//
// Development-time only -- nothing at runtime shells out to this. Hammerspoon
// cannot load SF Symbols itself (hs.image.imageFromName goes through
// NSImage(named:), which does not resolve symbol names), so the symbol is
// rendered ahead of time and the PNG checked in as an asset.
//
// Draws the symbol knocked out of a filled rounded rect, so the cup is a real
// transparent hole and picks up whatever the menu bar is behind it -- the same
// look macOS gives a highlighted menu bar item. The result is a COLOUR image,
// so keybinds_caffeine.lua must set it with template=false or macOS will
// flatten the fill to a monochrome tint.
//
// Regenerate with:
//   swift helpers/coffee-icon.swift cup.and.saucer.fill 0.00 0.48 1.00 2 assets/coffee-active.png
//
// Args: <symbol> <r> <g> <b> <scale> <out.png>, colour components 0..1.
import AppKit

let a = CommandLine.arguments
guard a.count >= 7,
      let r = Double(a[2]), let g = Double(a[3]), let b = Double(a[4]),
      let scale = Double(a[5]) else {
    FileHandle.standardError.write(
        "usage: coffee-icon <symbol> <r> <g> <b> <scale> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = a[6]

// Sized for the menu bar: the bar's content area is about 22pt, so a 20pt
// pill sits inside it without being scaled down and blurred.
let pillW: CGFloat = 28, pillH: CGFloat = 20, radius: CGFloat = 5
let symbolPoints: CGFloat = 12

let cfg = NSImage.SymbolConfiguration(pointSize: symbolPoints, weight: .regular)
guard let symbol = NSImage(systemSymbolName: a[1], accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {
    FileHandle.standardError.write("symbol not found: \(a[1])\n".data(using: .utf8)!)
    exit(1)
}

let size = NSSize(width: pillW, height: pillH)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(pillW * CGFloat(scale)),
                                 pixelsHigh: Int(pillH * CGFloat(scale)),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(srgbRed: r, green: g, blue: b, alpha: 1).set()
NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
             xRadius: radius, yRadius: radius).fill()

// destinationOut clears the pill wherever the symbol is opaque
let sx = (pillW - symbol.size.width) / 2
let sy = (pillH - symbol.size.height) / 2
symbol.draw(in: NSRect(x: sx, y: sy, width: symbol.size.width, height: symbol.size.height),
            from: .zero, operation: .destinationOut, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("\(outPath): \(Int(pillW))x\(Int(pillH))pt at \(Int(scale))x, "
      + "symbol \(Int(symbol.size.width))x\(Int(symbol.size.height))pt")
