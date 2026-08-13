// One-shot generator: render an SF Symbol to a template-ready PNG with alpha.
//
// Development-time only -- nothing at runtime shells out to this. Hammerspoon
// cannot load SF Symbols itself (hs.image.imageFromName goes through
// NSImage(named:), which does not resolve symbol names), so the symbol is
// rendered ahead of time and the PNG checked in as an asset.
//
// Regenerate the menu bar coffee cup with:
//   swift helpers/coffee-icon.swift cup.and.saucer.fill 15 2 assets/coffee-template.png
//
// The trailing arg pair is point size and scale factor: 2 gives a Retina-density
// bitmap that keybinds_caffeine.lua scales back down to its point size.
import AppKit

let args = CommandLine.arguments
guard args.count >= 5,
      let pointSize = Double(args[2]),
      let scale = Double(args[3]) else {
    FileHandle.standardError.write("usage: rendersymbol <symbol> <pointSize> <scale> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let symbolName = args[1]
let outPath = args[4]

let config = NSImage.SymbolConfiguration(pointSize: CGFloat(pointSize), weight: .regular)
guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
    FileHandle.standardError.write("symbol not found: \(symbolName)\n".data(using: .utf8)!)
    exit(1)
}

let size = symbol.size
let pixelW = Int((size.width * CGFloat(scale)).rounded())
let pixelH = Int((size.height * CGFloat(scale)).rounded())

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelW, pixelsHigh: pixelH,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    exit(1)
}
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.black.set()
let rect = NSRect(origin: .zero, size: size)
symbol.draw(in: rect)
rect.fill(using: .sourceAtop)   // force pure black; alpha carries the shape
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("\(pixelW)x\(pixelH) px, \(Int(size.width))x\(Int(size.height)) pt")
