import Foundation

struct DroppedInput: Equatable, Sendable {}

struct AcceptedDrop: Equatable, Sendable {
    let input: DroppedInput
}

enum OutputFormat: Equatable, Sendable {
    case jpeg
    case png
}

struct DropGeneration: Equatable, Sendable {
    let value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }
}

struct ConversionRequest: Equatable, Sendable {
    let generation: DropGeneration
    let input: DroppedInput
    let format: OutputFormat
}

struct ConvertedImage: Equatable, Sendable {
    let requestedFormatData: Data
    let tiffData: Data
}

enum ImageConversionFailure: Error, Equatable, Sendable {
    case failed
}

struct ClipboardHandoff: Equatable, Sendable {
    let generation: DropGeneration
    let format: OutputFormat
    let requestedFormatData: Data
    let tiffData: Data
}
