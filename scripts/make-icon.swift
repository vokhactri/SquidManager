// Draws the app icon and writes it as an .icns file: swift scripts/make-icon.swift <output.icns>
// Renders the shared SVG in white on a dark tile without requiring Xcode asset catalogs.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("Sources/SquidManager/Resources/squid.svg")
guard let squid = NSImage(contentsOf: source) else {
  fatalError("Could not load squid.svg at \(source.path)")
}

func draw(in ctx: CGContext) {
  // Apple's macOS icon grid puts an 824 pt rounded square in the middle of a 1024 pt canvas.
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
  let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
  ctx.addPath(tilePath)
  ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: 1))
  ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(tilePath)
  ctx.clip()
  let tileGradient = CGGradient(colorsSpace: rgb, colors: [
    CGColor(srgbRed: 0.17, green: 0.18, blue: 0.20, alpha: 1),
    CGColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: 1),
  ] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(tileGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

  // A subtle highlight follows the upper-left edge.
  ctx.addPath(tilePath)
  ctx.setLineWidth(8)
  ctx.replacePathWithStrokedPath()
  ctx.clip()
  let rimGradient = CGGradient(colorsSpace: rgb, colors: [
    CGColor(gray: 1, alpha: 0.25),
    CGColor(gray: 1, alpha: 0.04),
    CGColor(gray: 1, alpha: 0.08),
  ] as CFArray, locations: [0, 0.55, 1])!
  ctx.drawLinearGradient(
    rimGradient,
    start: CGPoint(x: 100, y: 924),
    end: CGPoint(x: 924, y: 100),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
  ctx.restoreGState()

  // Use the SVG's alpha as the mask for the white squid.
  ctx.beginTransparencyLayer(auxiliaryInfo: nil)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
  squid.draw(in: CGRect(x: 212, y: 212, width: 600, height: 600))
  NSGraphicsContext.restoreGraphicsState()
  ctx.setBlendMode(.sourceIn)
  ctx.setFillColor(CGColor(gray: 1, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
  ctx.endTransparencyLayer()
  ctx.setBlendMode(.normal)
}

func png(size: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
  ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  draw(in: ctx)
  return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory
  .appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
  try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
  try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
