import Foundation

nonisolated struct DroppedInput: Equatable, Sendable {
    // The caller keeps the source readable for the duration of conversion.
    let fileURL: URL
}

nonisolated struct AcceptedDrop: Equatable, Sendable {
    let input: DroppedInput
}

nonisolated enum OutputFormat: Equatable, Sendable {
    case jpeg
    case png
}

nonisolated struct DropID: Equatable, Sendable {
    let value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }
}

nonisolated struct ConversionRequest: Equatable, Sendable {
    let dropID: DropID
    let input: DroppedInput
    let format: OutputFormat
}

nonisolated struct ConvertedImage: Equatable, Sendable {
    let requestedFormatData: Data
    let tiffData: Data
}

nonisolated enum ImageConversionFailure: Error, Equatable, Sendable {
    case failed
}

nonisolated struct ClipboardHandoff: Equatable, Sendable {
    let dropID: DropID
    let format: OutputFormat
    let convertedImage: ConvertedImage
}
