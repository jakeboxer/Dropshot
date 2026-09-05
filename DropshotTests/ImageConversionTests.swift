import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

private final class FixtureBundle {}

struct ImageConversionTests {
    @Test
    func defaultConversionPreservesOrientedVisibleImageAsOwnedRepresentations() async throws {
        let fixture = try #require(Bundle(for: FixtureBundle.self)
            .url(forResource: "oriented-metadata", withExtension: "heic"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.heic")
        let original = try Data(contentsOf: fixture)
        try original.write(to: input)

        let result = await ImageConversion().convert(ConversionRequest(
            dropID: DropID(1), input: DroppedInput(fileURL: input), format: .jpeg))
        let output = try result.get()
        let repeated = try await ImageConversion().convert(ConversionRequest(
            dropID: DropID(2), input: DroppedInput(fileURL: input), format: .jpeg)).get()
        #expect(repeated == output)

        #expect(try Data(contentsOf: input) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["input.heic"])
        try FileManager.default.removeItem(at: input)
        for (data, type) in [(output.requestedFormatData, UTType.jpeg), (output.tiffData, UTType.tiff)] {
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
            #expect((properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1)
            #expect(!String(describing: properties).contains("Dropshot private"))
            #expect(!String(describing: properties).contains("Dropshot fixture artist"))
        }
    }

    @Test(arguments: 1...8)
    func appliesEveryEXIFOrientationToFullResolutionPixels(_ orientation: Int) async throws {
        let output = try await convertFixture("orientation-\(orientation)")
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

    @Test
    func convertsOnlyPrimaryStillImage() async throws {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "primary-second", withExtension: "heic"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
        #expect(CGImageSourceGetPrimaryImageIndex(source) == 1)
        let output = try await convertFixture("primary-second")
        for data in [output.requestedFormatData, output.tiffData] {
            let converted = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetCount(converted) == 1)
            let image = try #require(CGImageSourceCreateImageAtIndex(converted, 0, nil))
            #expect(image.width == 96)
            #expect(image.height == 64)
            try expectCorners(image, colors: [[255, 255, 255], [255, 127, 127], [0, 0, 255], [255, 255, 0]])
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

private func expectCorners(_ image: CGImage, colors: [[Int]]) throws {
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    for (index, point) in [(image.width / 4, image.height / 4),
                            (image.width * 3 / 4, image.height / 4),
                            (image.width / 4, image.height * 3 / 4),
                            (image.width * 3 / 4, image.height * 3 / 4)].enumerated() {
        for channel in 0..<3 {
            #expect(abs(Int(bytes[(point.1 * image.width + point.0) * 4 + channel]) - colors[index][channel]) <= 12)
        }
    }
}

private func convertFixture(_ name: String) async throws -> ConvertedImage {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "heic"))
    return try await ImageConversion().convert(ConversionRequest(
        dropID: DropID(1), input: DroppedInput(fileURL: url), format: .jpeg)).get()
}
