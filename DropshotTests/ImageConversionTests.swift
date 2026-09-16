import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

private final class FixtureBundle {}

struct ImageConversionTests {
    @Test(arguments: [OutputFormat.jpeg, .png])
    func absentColorUsesStandardHEICInterpretation(format: OutputFormat) async throws {
        let output = try await convertFixture("absent-color", format: format)
        for data in [output.requestedFormatData, output.tiffData] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 32)
            #expect(image.height == 24)
            #expect(image.bitsPerComponent == 8)
            #expect(image.colorSpace?.name == CGColorSpace.sRGB)
            try expectCorners(image, colors: [[128, 102, 77], [77, 140, 102],
                                              [77, 102, 153], [128, 128, 128]])
        }
    }

    @Test(arguments: [OutputFormat.jpeg, .png])
    func discardsRealAuxiliaryImageWhilePreservingPrimaryPixels(format: OutputFormat) async throws {
        let url = try #require(Bundle(for: FixtureBundle.self)
            .url(forResource: "disparity-auxiliary", withExtension: "heic"))
        let input = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(input,
            CGImageSourceGetPrimaryImageIndex(input), kCGImageAuxiliaryDataTypeDisparity) != nil)
        let output = try await convertFixture("disparity-auxiliary", format: format)
        for data in [output.requestedFormatData, output.tiffData] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetCount(source) == 1)
            for type in [kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
                         kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap] {
                #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) == nil)
            }
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 32)
            #expect(image.height == 24)
            try expectCorners(image, colors: [[128, 102, 77], [77, 140, 102],
                                              [77, 102, 153], [128, 128, 128]])
        }
    }

    @Test(arguments: [OutputFormat.jpeg, .png])
    func normalizesDisplayP3PixelsToSDRsRGB(format: OutputFormat) async throws {
        let output = try await convertFixture("display-p3", format: format)
        for (data, tolerance) in [(output.requestedFormatData, format == .jpeg ? 12 : 4),
                                  (output.tiffData, 4)] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 32)
            #expect(image.height == 24)
            #expect(image.bitsPerComponent == 8)
            #expect(image.colorSpace?.name == CGColorSpace.sRGB)
            // Independently calculated from Display P3 primaries and the sRGB transfer curve.
            try expectCorners(image, colors: [[132, 101, 73], [49, 142, 99],
                                              [69, 103, 157], [128, 128, 128]], tolerance: tolerance)
            try expectReferenceRaster(image, named: "reference-display-p3", tolerance: tolerance)
        }
    }

    @Test(arguments: ["malformed-color", "malformed-icc", "malformed-icc-size",
                      "malformed-size", "contradictory-color"], [OutputFormat.jpeg, .png])
    func malformedColorFailsWithoutRepresentations(_ fixture: String, format: OutputFormat) async throws {
        let url = try #require(Bundle(for: FixtureBundle.self)
            .url(forResource: fixture, withExtension: "heic"))
        let original = try Data(contentsOf: url)
        let result = await ImageConversion().convert(ConversionRequest(
            dropID: DropID(1), input: DroppedInput(fileURL: url), format: format))
        #expect(result == .failure(.failed))
        #expect(try Data(contentsOf: url) == original)
    }

    @Test(arguments: [OutputFormat.jpeg, .png])
    func preservesFullResolutionForLargeInputs(format: OutputFormat) async throws {
        let output = try await convertFixture("12-megapixel", format: format)
        for data in [output.requestedFormatData, output.tiffData] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 4000)
            #expect(image.height == 3000)
            #expect(image.bitsPerComponent == 8)
            #expect(image.colorSpace?.name == CGColorSpace.sRGB)
            // The large fixture's opaque source raster composites the clear
            // and half-red quadrants onto black before HEIC encoding.
            try expectCorners(image, colors: [[0, 0, 0], [128, 0, 0],
                                              [0, 0, 255], [255, 255, 0]])
        }
    }

    @Test
    func formatOverridePreservesAlphaInPNGAndTIFFFallback() async throws {
        let output = try await convertFixture("transparency", format: .png)
        for (data, type) in [(output.requestedFormatData, UTType.png), (output.tiffData, UTType.tiff)] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(source) == type.identifier as CFString)
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 96)
            #expect(image.height == 64)
            #expect(image.bitsPerComponent == 8)
            #expect(image.colorSpace?.name == CGColorSpace.sRGB)
            // Premultiplied RGBA: clear, half-alpha red, opaque blue, opaque yellow.
            try expectCorners(image, colors: [[0, 0, 0, 0], [128, 0, 0, 128], [0, 0, 255, 255], [255, 255, 0, 255]])
            try expectReferenceRaster(image, named: "reference-transparency")
        }
    }

    @Test(arguments: [OutputFormat.jpeg, .png])
    func conversionPreservesOrientedVisibleImageAsOwnedRepresentations(format: OutputFormat) async throws {
        let fixture = try #require(Bundle(for: FixtureBundle.self)
            .url(forResource: "oriented-metadata", withExtension: "heic"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.heic")
        let original = try Data(contentsOf: fixture)
        try original.write(to: input)

        let result = await ImageConversion().convert(ConversionRequest(
            dropID: DropID(1), input: DroppedInput(fileURL: input), format: format))
        let output = try result.get()
        let repeated = try await ImageConversion().convert(ConversionRequest(
            dropID: DropID(2), input: DroppedInput(fileURL: input), format: format)).get()
        #expect(repeated == output)

        #expect(try Data(contentsOf: input) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["input.heic"])
        try FileManager.default.removeItem(at: input)
        for (data, type) in [(output.requestedFormatData, format == .png ? UTType.png : .jpeg), (output.tiffData, UTType.tiff)] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(source) == type.identifier as CFString)
            #expect(CGImageSourceGetCount(source) == 1)
            for auxiliaryType in [kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
                                  kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap] {
                #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType) == nil)
            }
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 64)
            #expect(image.height == 96)
            #expect(image.bitsPerComponent == 8)
            #expect(image.colorSpace?.name == CGColorSpace.sRGB)
            // EXIF 6 rotates clockwise: blue, red / yellow, green.
            try expectCorners(image, colors: [[0, 0, 255], [255, 0, 0], [255, 255, 0], [0, 255, 0]])
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
            #expect(properties[kCGImagePropertyIPTCDictionary as String] == nil)
            #expect((properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1)
            #expect(!String(describing: properties).contains("Dropshot private"))
            #expect(!String(describing: properties).contains("Dropshot fixture artist"))
        }
    }

    @Test(arguments: 1...8, [OutputFormat.jpeg, .png])
    func appliesEveryEXIFOrientationToFullResolutionPixels(_ orientation: Int, format: OutputFormat) async throws {
        let output = try await convertFixture("orientation-\(orientation)", format: format)
        let expected = [
            [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]],
            [[0, 255, 0], [255, 0, 0], [255, 255, 0], [0, 0, 255]],
            [[255, 255, 0], [0, 0, 255], [0, 255, 0], [255, 0, 0]],
            [[0, 0, 255], [255, 255, 0], [255, 0, 0], [0, 255, 0]],
            [[255, 0, 0], [0, 0, 255], [0, 255, 0], [255, 255, 0]],
            [[0, 0, 255], [255, 0, 0], [255, 255, 0], [0, 255, 0]],
            [[255, 255, 0], [0, 255, 0], [0, 0, 255], [255, 0, 0]],
            [[0, 255, 0], [255, 255, 0], [255, 0, 0], [0, 0, 255]]
        ]
        for data in [output.requestedFormatData, output.tiffData] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == (orientation >= 5 ? 64 : 96))
            #expect(image.height == (orientation >= 5 ? 96 : 64))
            try expectCorners(image, colors: expected[orientation - 1])
            try expectReferenceRaster(image, named: "reference-orientation-\(orientation)")
        }
    }

    @Test
    func defaultConversionCompositesTransparencyOntoWhite() async throws {
        let output = try await convertFixture("transparency")
        for data in [output.requestedFormatData, output.tiffData] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
            try expectCorners(image, colors: [[255, 255, 255], [255, 127, 127], [0, 0, 255], [255, 255, 0]])
        }
    }

    @Test(arguments: [OutputFormat.jpeg, .png])
    func convertsOnlyPrimaryStillImage(format: OutputFormat) async throws {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "primary-second", withExtension: "heic"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(CGImageSourceGetPrimaryImageIndex(source) == 1)
        let output = try await convertFixture("primary-second", format: format)
        for data in [output.requestedFormatData, output.tiffData] {
            let converted = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetCount(converted) == 1)
            let image = try #require(CGImageSourceCreateImageAtIndex(converted, 0, nil))
            #expect(image.width == 96)
            #expect(image.height == 64)
            try expectCorners(image, colors: format == .png
                ? [[0, 0, 0, 0], [128, 0, 0, 128], [0, 0, 255, 255], [255, 255, 0, 255]]
                : [[255, 255, 255], [255, 127, 127], [0, 0, 255], [255, 255, 0]])
        }
    }

    @Test
    func unreadableOrMalformedInputFailsWithoutRepresentations() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".heic")
        defer { try? FileManager.default.removeItem(at: url) }
        for data in [nil, Data("not an HEIC".utf8)] as [Data?] {
            if let data { try data.write(to: url) }
            let result = await ImageConversion().convert(ConversionRequest(
                dropID: DropID(1), input: DroppedInput(fileURL: url), format: .jpeg))
            #expect(result == .failure(.failed))
        }
    }

}

/// Compare every interior chart pixel, excluding four pixels around lossy
/// chroma boundaries. References are constructed independently of ImageIO and
/// the production converter; hashes establish integrity, never correctness.
private func expectReferenceRaster(_ image: CGImage, named name: String, tolerance: Int = 12) throws {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "png"))
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let reference = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    try #require(image.width == reference.width && image.height == reference.height)
    let actual = try rgbaPixels(image)
    let expected = try rgbaPixels(reference)
    let halfWidth = image.width / 2
    let halfHeight = image.height / 2
    var maximumError = 0
    for y in 0..<image.height where (4..<(halfHeight - 4)).contains(y % halfHeight) {
        for x in 0..<image.width where (4..<(halfWidth - 4)).contains(x % halfWidth) {
            for channel in 0..<4 {
                let index = (y * image.width + x) * 4 + channel
                maximumError = max(maximumError, abs(Int(actual[index]) - Int(expected[index])))
            }
        }
    }
    #expect(maximumError <= tolerance)
}

private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4))
}

private func expectCorners(_ image: CGImage, colors: [[Int]], tolerance: Int = 12) throws {
    let bytes = try rgbaPixels(image)
    for (index, point) in [(image.width / 4, image.height / 4),
                            (image.width * 3 / 4, image.height / 4),
                            (image.width / 4, image.height * 3 / 4),
                            (image.width * 3 / 4, image.height * 3 / 4)].enumerated() {
        for channel in colors[index].indices {
            #expect(abs(Int(bytes[(point.1 * image.width + point.0) * 4 + channel]) - colors[index][channel]) <= tolerance)
        }
    }
}

private func convertFixture(_ name: String, format: OutputFormat = .jpeg) async throws -> ConvertedImage {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "heic"))
    return try await ImageConversion().convert(ConversionRequest(
        dropID: DropID(1), input: DroppedInput(fileURL: url), format: format)).get()
}
