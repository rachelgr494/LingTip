// Generates app + menu-bar icons from the logo PNG and prints its key colors.
// Usage: swiftc -O Scripts/make_icons.swift -o /tmp/make_icons && /tmp/make_icons "LingTip Translation Logo.png" Support/Icons
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: make_icons <logo.png> <outDir>"); exit(2) }
let inputURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("cannot read logo"); exit(1) }

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgbaBuffer(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (data, w, h)
}

// MARK: Colors (bitmap row 0 is the top of the image)

let full = rgbaBuffer(logo)
func hex(atTopLeft x: Int, _ y: Int) -> String {
    let i = (y * full.w + x) * 4
    return String(format: "#%02X%02X%02X", full.data[i], full.data[i + 1], full.data[i + 2])
}
print("background  ", hex(atTopLeft: 30, 30))
print("bubble gold ", hex(atTopLeft: 420, 330))
print("bubble orng ", hex(atTopLeft: 370, 560))
print("bubble pink ", hex(atTopLeft: 810, 500))
print("star gold   ", hex(atTopLeft: 862, 290))
print("star pink   ", hex(atTopLeft: 950, 365))
print("wordmark    ", hex(atTopLeft: 262, 850))
print("T pink      ", hex(atTopLeft: 752, 850))
print("p orange    ", hex(atTopLeft: 1000, 880))

// MARK: Glyph crop (bubble, cursor, sparkles; stops above the wordmark)

let cropRect = CGRect(x: 305, y: 50, width: 695, height: 695)
let glyph = logo.cropping(to: cropRect)!

func save(_ image: CGImage, _ name: String) {
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: App icon: glyph on a rounded navy tile with the standard macOS margin

func renderAppIcon(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size)
    let tile = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let radius = tile.width * 0.2237
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(glyph, in: tile)
    return ctx.makeImage()!
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    let one = renderAppIcon(size: base), two = renderAppIcon(size: base * 2)
    let d1 = CGImageDestinationCreateWithURL(iconset.appendingPathComponent("icon_\(base)x\(base).png") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d1, one, nil); CGImageDestinationFinalize(d1)
    let d2 = CGImageDestinationCreateWithURL(iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d2, two, nil); CGImageDestinationFinalize(d2)
}
save(renderAppIcon(size: 1024), "AppIcon-1024.png")

// MARK: Menu bar template: silhouette. Flood-fill the dark background from the corner;
// everything not reached (bubble ring, its enclosed interior, cursor, sparkles) is opaque.

// The cursor's dark drop shadow cuts a thin dark channel through the ring, so a naive
// flood fill leaks into the bubble. Dilate the bright shape first to seal such gaps.
let g = rgbaBuffer(glyph)
let w = g.w, h = g.h
func lum(_ i: Int) -> Int { (Int(g.data[i]) * 299 + Int(g.data[i + 1]) * 587 + Int(g.data[i + 2]) * 114) / 1000 }
let neighbors = [(1, 0), (-1, 0), (0, 1), (0, -1)]

func dilate(_ set: [Bool], by radius: Int) -> [Bool] {
    var out = set
    var frontier = (0..<(w * h)).filter { set[$0] }
    for _ in 0..<radius {
        var next: [Int] = []
        for p in frontier {
            let x = p % w, y = p / w
            for (dx, dy) in neighbors {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let n = ny * w + nx
                if !out[n] { out[n] = true; next.append(n) }
            }
        }
        frontier = next
    }
    return out
}

func flood(from start: Int, over allowed: (Int) -> Bool) -> [Bool] {
    var reached = [Bool](repeating: false, count: w * h)
    var stack = [start]
    reached[start] = true
    while let p = stack.popLast() {
        let x = p % w, y = p / w
        for (dx, dy) in neighbors {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
            let n = ny * w + nx
            if !reached[n], allowed(n) { reached[n] = true; stack.append(n) }
        }
    }
    return reached
}

let sealRadius = 10
let bright = (0..<(w * h)).map { lum($0 * 4) >= 60 }
let sealed = dilate(bright, by: sealRadius)
let outside = flood(from: 0) { !sealed[$0] }
// Opaque = bright, or anything not within sealRadius of the outside (fills the bubble,
// including the gaps between the letter strokes, without growing the outer edge).
let nearOutside = dilate(outside, by: sealRadius)

var minX = w, minY = h, maxX = 0, maxY = 0
var mask = [UInt8](repeating: 0, count: w * h * 4)
for y in 0..<h { for x in 0..<w {
    let n = y * w + x
    if bright[n] || !nearOutside[n] {
        mask[n * 4 + 3] = 255
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
} }
let maskCtx = CGContext(data: &mask, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let silhouette = maskCtx.makeImage()!.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

func renderTemplate(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let s = CGFloat(size), pad = s * 0.04
    let avail = s - 2 * pad
    let aspect = CGFloat(silhouette.width) / CGFloat(silhouette.height)
    let dw = aspect >= 1 ? avail : avail * aspect
    let dh = aspect >= 1 ? avail / aspect : avail
    ctx.draw(silhouette, in: CGRect(x: (s - dw) / 2, y: (s - dh) / 2, width: dw, height: dh))
    return ctx.makeImage()!
}
save(renderTemplate(size: 18), "MenuBarIconTemplate.png")
save(renderTemplate(size: 36), "MenuBarIconTemplate@2x.png")
save(renderTemplate(size: 256), "MenuBarIcon-preview.png")

// Settings header: the full logo, downscaled.
func downscale(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}
save(downscale(logo, to: 256), "Logo.png")
save(downscale(logo, to: 512), "Logo@2x.png")
print("done →", outDir.path)
