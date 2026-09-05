struct DropWorkflow {
    enum Event: Sendable {
        case dragObserved(DragDescriptor)
        case modifiersChanged(optionHeld: Bool)
        case acceptedDrop(AcceptedDrop)
        case conversionCompleted(
            request: ConversionRequest,
            result: Result<ConvertedImage, ImageConversionFailure>
        )
        case clipboardHandoffCompleted(dropID: DropID)
        case clipboardHandoffFailed(dropID: DropID)
    }

    nonisolated enum Effect: Equatable, Sendable {
        case convert(ConversionRequest)
        case performClipboardHandoff(ClipboardHandoff)
    }

    private(set) var isDropZoneRequested = false
    private(set) var activeDropID: DropID?
    private(set) var selectedFormat: OutputFormat = .jpeg
    private var nextDropID = DropID(1)

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .dragObserved(let descriptor):
            isDropZoneRequested = DragClassifier.classify(descriptor) == .eligible
            return []

        case .modifiersChanged(let optionHeld):
            selectedFormat = FormatSelection.resolve(optionHeld: optionHeld)
            return []

        case .acceptedDrop(let acceptedDrop):
            isDropZoneRequested = false
            selectedFormat = FormatSelection.resolve(optionHeld: acceptedDrop.optionHeld)
            let request = ConversionRequest(
                dropID: nextDropID,
                input: acceptedDrop.input,
                format: selectedFormat
            )
            activeDropID = nextDropID
            nextDropID = DropID(nextDropID.value + 1)
            return [.convert(request)]

        case .conversionCompleted(let request, .success(let image)):
            guard request.dropID == activeDropID else {
                return []
            }
            return [
                .performClipboardHandoff(
                    ClipboardHandoff(
                        dropID: request.dropID,
                        format: request.format,
                        convertedImage: image
                    )
                )
            ]

        case .conversionCompleted(let request, .failure):
            guard request.dropID == activeDropID else {
                return []
            }
            activeDropID = nil
            return []

        case .clipboardHandoffCompleted(let dropID),
             .clipboardHandoffFailed(let dropID):
            guard dropID == activeDropID else {
                return []
            }
            activeDropID = nil
            return []
        }
    }
}
