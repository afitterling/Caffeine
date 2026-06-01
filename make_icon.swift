import AppKit

// Render a circular gradient with an SF Symbol on top, save at all standard
// iconset sizes, then call iconutil to produce AppIcon.icns.
let symbolName = "cup.and.saucer.fill"
let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func render(size px: Int) -> Data? {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-square mask (macOS Big Sur+ icon shape).
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = (s - inset * 2) * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    path.addClip()

    // Warm sunrise gradient.
    let top    = NSColor(calibratedRed: 1.00, green: 0.71, blue: 0.40, alpha: 1) // peach
    let bottom = NSColor(calibratedRed: 0.95, green: 0.36, blue: 0.50, alpha: 1) // coral
    let gradient = NSGradient(colors: [top, bottom])!
    gradient.draw(in: rect, angle: -90)

    // SF Symbol on top.
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.55, weight: .semibold)
        .applying(.init(paletteColors: [NSColor.white]))
    if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sw = symbol.size.width
        let sh = symbol.size.height
        let r = CGRect(
            x: (s - sw) / 2,
            y: (s - sh) / 2 - s * 0.02,
            width: sw, height: sh
        )
        // Soft shadow under the symbol for depth.
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01),
                      blur: s * 0.025,
                      color: NSColor.black.withAlphaComponent(0.25).cgColor)
        symbol.draw(in: r)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = render(size: px) else { continue }
    let path = "\(outDir)/\(name)"
    try? data.write(to: URL(fileURLWithPath: path))
    print("  · \(name)")
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", outDir, "-o", "AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ AppIcon.icns built" : "✗ iconutil failed")
