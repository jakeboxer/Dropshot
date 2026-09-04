struct DropWorkflow {
    enum Event: Sendable {
        case acceptedDrop(AcceptedDrop)
        case conversionCompleted(
            request: ConversionRequest,
            result: Result<ConvertedImage, ImageConversionFailure>
        )
        case clipboardHandoffCompleted(generation: DropGeneration)
        case clipboardHandoffFailed(generation: DropGeneration)
    }

    enum Effect: Equatable, Sendable {
        case convert(ConversionRequest)
        case performClipboardHandoff(ClipboardHandoff)
    }

    private(set) var activeGeneration: DropGeneration?
    private var nextGeneration = DropGeneration(1)

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .acceptedDrop(let acceptedDrop):
            let request = ConversionRequest(
                generation: nextGeneration,
                input: acceptedDrop.input,
                format: .jpeg
            )
            activeGeneration = nextGeneration
            nextGeneration = DropGeneration(nextGeneration.value + 1)
            return [.convert(request)]

        case .conversionCompleted(let request, .success(let image)):
            guard request.generation == activeGeneration else {
                return []
            }
            return [
                .performClipboardHandoff(
                    ClipboardHandoff(
                        generation: request.generation,
                        format: request.format,
                        requestedFormatData: image.requestedFormatData,
                        tiffData: image.tiffData
                    )
                )
            ]

        case .conversionCompleted(let request, .failure):
            guard request.generation == activeGeneration else {
                return []
            }
            activeGeneration = nil
            return []

        case .clipboardHandoffCompleted(let generation),
             .clipboardHandoffFailed(let generation):
            guard generation == activeGeneration else {
                return []
            }
            activeGeneration = nil
            return []
        }
    }
}
