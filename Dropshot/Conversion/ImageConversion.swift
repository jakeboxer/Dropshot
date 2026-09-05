import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Converts a readable HEIC source into eagerly owned clipboard representations.
/// Source access and its lifetime belong to the caller, not the image pipeline.
nonisolated struct ImageConversion: ImageConverting {
    @concurrent
    func convert(_ request: ConversionRequest) async -> Result<ConvertedImage, ImageConversionFailure> {
        autoreleasepool {
            do {
                guard request.format == .jpeg, request.input.fileURL.isFileURL else {
                    throw ImageConversionFailure.failed
                }
                // Drain decoder intermediates before preparing the two encoded buffers.
                let raster = try autoreleasepool { try visibleImage(at: request.input.fileURL) }
                return .success(ConvertedImage(
                    requestedFormatData: try autoreleasepool { try encode(raster, type: .jpeg) },
                    tiffData: try autoreleasepool { try encode(raster, type: .tiff) }
                ))
            } catch {
                return .failure(.failed)
            }
        }
    }

    private func visibleImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) == UTType.heic.identifier as CFString else {
            throw ImageConversionFailure.failed
        }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let options: [CFString: Any] = [
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToSDR,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateImageAtIndex(source, index, options as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageConversionFailure.failed
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        guard (1...8).contains(orientation) else { throw ImageConversionFailure.failed }
        let swapsDimensions = orientation >= 5
        let width = swapsDimensions ? image.height : image.width
        let height = swapsDimensions ? image.width : image.height
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageConversionFailure.failed
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // EXIF transforms in Core Graphics' bottom-left coordinate system.
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let transform: CGAffineTransform
        switch orientation {
        case 2: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case 3: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 4: transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case 5: transform = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 6: transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case 7: transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 8: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        default: transform = .identity
        }
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raster = context.makeImage() else { throw ImageConversionFailure.failed }
        return raster
    }

    private func encode(_ image: CGImage, type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ImageConversionFailure.failed
        }
        // Encode a fresh raster, never copy source properties or auxiliary data.
        var properties: [CFString: Any] = [kCGImageDestinationEmbedThumbnail: false]
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.90
        } else {
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] // Lossless LZW.
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageConversionFailure.failed }
        return Data(referencing: data)
    }
}
