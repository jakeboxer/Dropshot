// Run with: swift scripts/generate-conversion-policy-fixtures.swift DropshotTests/Fixtures
//
// These fixtures are compact, synthetic, and owned by this project. ImageIO's
// HEIC encoder supplies the container and compressed image data. The absent and
// malformed color fixtures then receive a narrow ISO-BMFF property edit because
// ImageIO does not expose an encoder option for either invalid or omitted color
// information. Every expected byte sequence is preconditioned before mutation.
// HEIC bytes may change across macOS encoder versions; the analytical raster and
// container properties below are the reproducible provenance. The fixture set
// was first generated on macOS 26.6.2 (25G83), Apple M1 Max, using the macOS
// 27.0 SDK. No photographs or third-party source data are involved.

import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: swift scripts/generate-conversion-policy-fixtures.swift <output-directory>")
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let width = 32
let height = 24

func makeChart(colorSpace: CGColorSpace) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!

    // In displayed (top-left) order, three interior colors and neutral gray.
    // The non-neutral colors distinguish a real Display-P3-to-sRGB conversion
    // from merely assigning an sRGB label to the source component values.
    for (rect, components) in [
        (CGRect(x: 0, y: 12, width: 16, height: 12), [0.50, 0.40, 0.30, 1.0]),
        (CGRect(x: 16, y: 12, width: 16, height: 12), [0.30, 0.55, 0.40, 1.0]),
        (CGRect(x: 0, y: 0, width: 16, height: 12), [0.30, 0.40, 0.60, 1.0]),
        (CGRect(x: 16, y: 0, width: 16, height: 12), [0.5, 0.5, 0.5, 1.0]),
    ] {
        context.setFillColor(CGColor(
            colorSpace: colorSpace,
            components: components.map { CGFloat($0) }
        )!)
        context.fill(rect)
    }

    return context.makeImage()!
}

func encode(_ image: CGImage, to url: URL, addAuxiliaryData: ((CGImageDestination) -> Void)? = nil) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.heic.identifier as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: 1.0,
    ] as CFDictionary)
    addAuxiliaryData?(destination)
    precondition(CGImageDestinationFinalize(destination), "could not encode \(url.lastPathComponent)")
}

func uniqueRange(of needle: [UInt8], in bytes: [UInt8], label: String) -> Range<Int> {
    let matches = bytes.indices.compactMap { start -> Range<Int>? in
        let end = start + needle.count
        guard end <= bytes.endIndex, bytes[start..<end].elementsEqual(needle) else { return nil }
        return start..<end
    }
    precondition(matches.count == 1, "expected one \(label), found \(matches.count)")
    return matches[0]
}

func writeAbsentColorFixture(from source: URL, to output: URL) throws {
    var bytes = [UInt8](try Data(contentsOf: source))
    let colorProperty = uniqueRange(
        of: Array("colrnclx".utf8),
        in: bytes,
        label: "nclx color property"
    )
    bytes.replaceSubrange(colorProperty.lowerBound..<(colorProperty.lowerBound + 4), with: "free".utf8)

    // ImageIO marks property 1 (`colr`) essential in this generated file. Once
    // it becomes an unknown free-space property, make that association optional
    // so a conforming reader can decode using its standard HEIC interpretation.
    let association = uniqueRange(
        of: [0x00, 0x01, 0x06, 0x81, 0x02, 0x03, 0x05, 0x86, 0x84],
        in: bytes,
        label: "primary-item property association"
    )
    bytes[association.lowerBound + 3] = 0x01
    try Data(bytes).write(to: output, options: .atomic)
}

func writeMalformedColorFixture(from source: URL, to output: URL) throws {
    var bytes = [UInt8](try Data(contentsOf: source))
    let colorProperty = uniqueRange(
        of: Array("colrnclx".utf8),
        in: bytes,
        label: "nclx color property"
    )
    // nclx begins with three big-endian UInt16 values: primaries, transfer
    // function, and matrix. 0xffff is not an ISO/IEC 23091-2 primaries code.
    // ImageIO currently decodes this by silently substituting sRGB; the fixture
    // exists to ensure Dropshot detects the malformed source instead of relying
    // on that fallback.
    bytes[colorProperty.upperBound] = 0xff
    bytes[colorProperty.upperBound + 1] = 0xff
    try Data(bytes).write(to: output, options: .atomic)
}

func writeMalformedICCFixture(from source: URL, to output: URL) throws {
    var bytes = [UInt8](try Data(contentsOf: source))
    _ = uniqueRange(
        of: Array("colrprof".utf8),
        in: bytes,
        label: "embedded ICC color property"
    )
    let signature = uniqueRange(
        of: Array("acsp".utf8),
        in: bytes,
        label: "ICC header signature"
    )
    // ICC.1 requires the `acsp` signature at bytes 36...39 of the profile
    // header. Corrupt that field without changing the HEIF container layout.
    bytes.replaceSubrange(signature, with: "bad!".utf8)
    try Data(bytes).write(to: output, options: .atomic)
}

func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8(truncatingIfNeeded: value >> 24),
        UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value),
    ]
}

func nclxProperty(primaries: UInt16, transfer: UInt16, matrix: UInt16, fullRange: Bool) -> [UInt8] {
    bigEndianBytes(19)
        + Array("colrnclx".utf8)
        + [
            UInt8(primaries >> 8), UInt8(truncatingIfNeeded: primaries),
            UInt8(transfer >> 8), UInt8(truncatingIfNeeded: transfer),
            UInt8(matrix >> 8), UInt8(truncatingIfNeeded: matrix),
            fullRange ? 0x80 : 0x00,
        ]
}

func writeContradictoryColorFixture(from source: URL, to output: URL) throws {
    var bytes = [UInt8](try Data(contentsOf: source))
    let colorProperty = uniqueRange(
        of: Array("colrprof".utf8),
        in: bytes,
        label: "embedded ICC color property"
    )
    let boxStart = colorProperty.lowerBound - 4
    let boxSize = Int(
        UInt32(bytes[boxStart]) << 24
            | UInt32(bytes[boxStart + 1]) << 16
            | UInt32(bytes[boxStart + 2]) << 8
            | UInt32(bytes[boxStart + 3])
    )
    precondition(boxSize >= 46, "ICC property is too small for in-place replacement")

    // Two individually valid but conflicting declarations: sRGB/full-range
    // identity and BT.2020/PQ/nonconstant-luminance. A free property preserves
    // the original ICC property's exact byte length, so media offsets remain
    // unchanged and only the property indexes need updating.
    let first = nclxProperty(primaries: 1, transfer: 13, matrix: 0, fullRange: true)
    let second = nclxProperty(primaries: 9, transfer: 16, matrix: 9, fullRange: false)
    let freeSize = boxSize - first.count - second.count
    let free = bigEndianBytes(UInt32(freeSize)) + Array("free".utf8)
        + [UInt8](repeating: 0, count: freeSize - 8)
    let replacement = first + second + free
    precondition(replacement.count == boxSize)
    bytes.replaceSubrange(boxStart..<(boxStart + boxSize), with: replacement)

    // The replacement adds two properties ahead of the original remaining
    // properties. Keep six associations by dropping the optional clli entry:
    // colr 1, colr 2, ispe 5, pixi 7, hvcC 8, irot 6.
    let association = uniqueRange(
        of: [0x00, 0x01, 0x06, 0x81, 0x02, 0x03, 0x05, 0x86, 0x84],
        in: bytes,
        label: "primary-item property association"
    )
    bytes.replaceSubrange(
        (association.lowerBound + 3)..<association.upperBound,
        with: [0x81, 0x82, 0x05, 0x07, 0x88, 0x86]
    )
    try Data(bytes).write(to: output, options: .atomic)
}

func writeMalformedColorBoxSizeFixture(from source: URL, to output: URL) throws {
    var bytes = [UInt8](try Data(contentsOf: source))
    let colorProperty = uniqueRange(
        of: Array("colrnclx".utf8),
        in: bytes,
        label: "nclx color property"
    )
    let boxStart = colorProperty.lowerBound - 4
    bytes.replaceSubrange(boxStart..<(boxStart + 4), with: bigEndianBytes(UInt32.max))
    try Data(bytes).write(to: output, options: .atomic)
}

func writeMalformedICCSizeFixture(from source: URL, to output: URL) throws {
    var bytes = [UInt8](try Data(contentsOf: source))
    let colorProperty = uniqueRange(
        of: Array("colrprof".utf8),
        in: bytes,
        label: "embedded ICC color property"
    )
    let profileStart = colorProperty.upperBound
    precondition(Array(bytes[(profileStart + 36)..<(profileStart + 40)]) == Array("acsp".utf8))
    bytes.replaceSubrange(profileStart..<(profileStart + 4), with: bigEndianBytes(UInt32.max))
    try Data(bytes).write(to: output, options: .atomic)
}

func imageSource(at url: URL) -> CGImageSource {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        fatalError("could not open \(url.lastPathComponent)")
    }
    return source
}

let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
let p3Image = makeChart(colorSpace: displayP3)
let displayP3URL = directory.appendingPathComponent("display-p3.heic")
encode(p3Image, to: displayP3URL)
try writeMalformedICCFixture(
    from: displayP3URL,
    to: directory.appendingPathComponent("malformed-icc.heic")
)
try writeContradictoryColorFixture(
    from: displayP3URL,
    to: directory.appendingPathComponent("contradictory-color.heic")
)
try writeMalformedICCSizeFixture(
    from: displayP3URL,
    to: directory.appendingPathComponent("malformed-icc-size.heic")
)

let baseURL = directory.appendingPathComponent("color-edge-base.tmp.heic")
encode(makeChart(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!), to: baseURL)
defer { try? FileManager.default.removeItem(at: baseURL) }
try writeAbsentColorFixture(
    from: baseURL,
    to: directory.appendingPathComponent("absent-color.heic")
)
try writeMalformedColorFixture(
    from: baseURL,
    to: directory.appendingPathComponent("malformed-color.heic")
)
try writeMalformedColorBoxSizeFixture(
    from: baseURL,
    to: directory.appendingPathComponent("malformed-size.heic")
)

let auxiliaryURL = directory.appendingPathComponent("disparity-auxiliary.heic")
encode(makeChart(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!), to: auxiliaryURL) { destination in
    let auxiliaryWidth = 8
    let auxiliaryHeight = 6
    let values = (0..<(auxiliaryWidth * auxiliaryHeight)).map { Float32($0) / 47.0 }
    let data = values.withUnsafeBytes { Data($0) }
    let description: [CFString: Any] = [
        kCGImagePropertyWidth: auxiliaryWidth,
        kCGImagePropertyHeight: auxiliaryHeight,
        kCGImagePropertyBytesPerRow: auxiliaryWidth * MemoryLayout<Float32>.size,
        kCGImagePropertyPixelFormat: kCVPixelFormatType_DisparityFloat32,
    ]
    let auxiliaryInfo: [CFString: Any] = [
        kCGImageAuxiliaryDataInfoData: data,
        kCGImageAuxiliaryDataInfoDataDescription: description,
        kCGImageAuxiliaryDataInfoMetadata: CGImageMetadataCreateMutable(),
    ]
    CGImageDestinationAddAuxiliaryDataInfo(
        destination,
        kCGImageAuxiliaryDataTypeDisparity,
        auxiliaryInfo as CFDictionary
    )
}

let p3Source = imageSource(at: displayP3URL)
let p3Properties = CGImageSourceCopyPropertiesAtIndex(p3Source, 0, nil) as? [CFString: Any]
precondition(p3Properties?[kCGImagePropertyProfileName] as? String == "Display P3")
precondition(CGImageSourceCreateImageAtIndex(p3Source, 0, nil)?.colorSpace?.name == CGColorSpace.displayP3)

let absentSource = imageSource(at: directory.appendingPathComponent("absent-color.heic"))
precondition(CGImageSourceCreateImageAtIndex(absentSource, 0, nil) != nil)

let auxiliarySource = imageSource(at: auxiliaryURL)
precondition(CGImageSourceCopyAuxiliaryDataInfoAtIndex(
    auxiliarySource,
    0,
    kCGImageAuxiliaryDataTypeDisparity
) != nil)

print("Generated synthetic 32x24 fixtures with ImageIO on \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("- display-p3.heic: Display P3 source color space")
print("- absent-color.heic: optional unknown property in place of colr/nclx")
print("- malformed-color.heic: invalid nclx color-primaries code 65535")
print("- malformed-icc.heic: embedded Display P3 ICC with corrupt header signature")
print("- contradictory-color.heic: associated valid sRGB and BT.2020/PQ nclx properties")
print("- malformed-size.heic: nclx color property size exceeds its container")
print("- malformed-icc-size.heic: valid ICC signature with excessive declared profile size")
print("- disparity-auxiliary.heic: 8x6 Float32 disparity plane")
