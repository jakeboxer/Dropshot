// Run with: swift scripts/generate-heic-fixtures.swift DropshotTests/Fixtures
// Synthetic, project-owned color chart. No photographs or third-party source data.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 96, height: 64, bitsPerComponent: 8,
                        bytesPerRow: 0, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// In displayed (top-left) order: red, green / blue, yellow.
for (rect, color) in [
    (CGRect(x: 0, y: 32, width: 48, height: 32), [1.0, 0, 0, 1]),
    (CGRect(x: 48, y: 32, width: 48, height: 32), [0.0, 1, 0, 1]),
    (CGRect(x: 0, y: 0, width: 48, height: 32), [0.0, 0, 1, 1]),
    (CGRect(x: 48, y: 0, width: 48, height: 32), [1.0, 1, 0, 1])
] {
    context.setFillColor(CGColor(colorSpace: colorSpace, components: color.map { CGFloat($0) })!)
    context.fill(rect)
}
let destination = CGImageDestinationCreateWithURL(
    directory.appendingPathComponent("oriented-metadata.heic") as CFURL,
    UTType.heic.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, [
    kCGImagePropertyOrientation: 6,
    kCGImageDestinationLossyCompressionQuality: 1.0,
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Dropshot private fixture comment"],
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.0, kCGImagePropertyGPSLatitudeRef: "N"],
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Dropshot fixture artist"]
] as CFDictionary)
precondition(CGImageDestinationFinalize(destination))

func write(_ image: CGImage, name: String, orientation: Int = 1) {
    let output = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL,
        UTType.heic.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, image, [
        kCGImagePropertyOrientation: orientation,
        kCGImageDestinationLossyCompressionQuality: 1.0
    ] as CFDictionary)
    precondition(CGImageDestinationFinalize(output))
}
for orientation in 1...8 {
    write(context.makeImage()!, name: "orientation-\(orientation).heic", orientation: orientation)
}
// Transparent top-left, half-transparent red top-right, opaque blue/yellow below.
context.clear(CGRect(x: 0, y: 32, width: 96, height: 32))
context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
context.fill(CGRect(x: 48, y: 32, width: 48, height: 32))
write(context.makeImage()!, name: "transparency.heic")

let large = CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8,
    bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
large.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: 4000, height: 3000))
write(large.makeImage()!, name: "12-megapixel.heic")

// Two still images; only the second is primary. The first is a different-sized decoy.
let multiple = CGImageDestinationCreateWithURL(directory.appendingPathComponent("primary-second.heic") as CFURL,
    UTType.heic.identifier as CFString, 2, nil)!
CGImageDestinationAddImage(multiple, large.makeImage()!, [kCGImagePropertyPrimaryImage: false] as CFDictionary)
CGImageDestinationAddImage(multiple, context.makeImage()!, [kCGImagePropertyPrimaryImage: true] as CFDictionary)
precondition(CGImageDestinationFinalize(multiple))
