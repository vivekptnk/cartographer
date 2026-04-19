// MARK: - Placeholder Tile
// Grey-grid PNG returned on offline cache miss.
// Encoded once at first access and cached for the process lifetime.

import Foundation
import CoreGraphics
import ImageIO
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

enum PlaceholderTile {
    /// 256×256 grey-grid PNG. Returned when a tile is missing from cache and
    /// the network is unavailable. Never nil — falls back to a minimal
    /// single-pixel grey PNG if CoreGraphics encoding somehow fails.
    static let data: Data = {
        if let rendered = render() {
            return rendered
        }
        return fallbackGreyPixelPNG
    }()

    private static func render() -> Data? {
        let size = 256
        let bytesPerRow = size * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue

        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.setFillColor(CGColor(srgbRed: 0.88, green: 0.88, blue: 0.88, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        ctx.setStrokeColor(CGColor(srgbRed: 0.76, green: 0.76, blue: 0.76, alpha: 1.0))
        ctx.setLineWidth(1)

        let step = 32
        var pos = 0
        while pos <= size {
            let p = CGFloat(pos)
            ctx.move(to: CGPoint(x: p, y: 0))
            ctx.addLine(to: CGPoint(x: p, y: CGFloat(size)))
            ctx.move(to: CGPoint(x: 0, y: p))
            ctx.addLine(to: CGPoint(x: CGFloat(size), y: p))
            pos += step
        }
        ctx.strokePath()

        guard let image = ctx.makeImage() else { return nil }

        let pngUTI: CFString
        #if canImport(UniformTypeIdentifiers)
        pngUTI = UTType.png.identifier as CFString
        #else
        pngUTI = "public.png" as CFString
        #endif

        let buffer = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(buffer, pngUTI, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return buffer as Data
    }

    /// Precomputed 1×1 grey PNG. Used only if CoreGraphics rendering fails.
    private static let fallbackGreyPixelPNG: Data = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0x99, 0x63, 0xE8, 0xE8, 0xE8, 0x00,
        0x00, 0x00, 0x03, 0x00, 0x01, 0x5A, 0x9C, 0xD2,
        0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82
    ])
}
