nonisolated enum DropZonePresentation: Equatable, Sendable {
    case hidden
    case guidance(OutputFormat)
    case success(OutputFormat, dropID: DropID)
}

struct DropWorkflow {
    private enum InteractionState {
        case idle
        case observing
        case suppressedUntilMouseRelease
    }

    enum Event: Sendable {
        case dragObserved(DragDescriptor)
        case destinationEntered(optionHeld: Bool)
        case destinationUpdated(optionHeld: Bool)
        case destinationExited
        case destinationInteractionEnded
        case pointerStateChanged(DragPointerState)
        case mouseReleased
        case interrupted
        case cancelled
        case modifiersChanged(optionHeld: Bool)
        case acceptedDrop(AcceptedDrop)
        case conversionCompleted(
            request: ConversionRequest,
            result: Result<ConvertedImage, ImageConversionFailure>
        )
        case clipboardHandoffCompleted(dropID: DropID, format: OutputFormat)
        case clipboardHandoffFailed(dropID: DropID)
        case successFeedbackElapsed(dropID: DropID)
    }

    nonisolated enum Effect: Equatable, Sendable {
        case convert(ConversionRequest)
        case performClipboardHandoff(ClipboardHandoff)
        case dismissSuccessFeedback(after: Duration, dropID: DropID)
    }

    private(set) var presentation: DropZonePresentation = .hidden
    private(set) var activeDropID: DropID?
    private(set) var selectedFormat: OutputFormat = .jpeg
    private var nextDropID = DropID(1)
    private var interactionState: InteractionState = .idle

    var isDropZoneRequested: Bool {
        if case .guidance = presentation {
            true
        } else {
            false
        }
    }

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .dragObserved(let descriptor):
            guard interactionState != .suppressedUntilMouseRelease else {
                return []
            }
            presentation = DragClassifier.classify(descriptor) == .eligible
                ? .guidance(selectedFormat)
                : .hidden
            interactionState = presentation == .hidden ? .idle : .observing
            return []

        case .destinationEntered(let optionHeld),
             .destinationUpdated(let optionHeld):
            guard interactionState != .suppressedUntilMouseRelease else {
                return []
            }
            interactionState = .observing
            updateGuidance(optionHeld: optionHeld)
            return []

        case .destinationExited,
             .destinationInteractionEnded,
             .interrupted:
            interactionState = .suppressedUntilMouseRelease
            presentation = .hidden
            return []

        case .cancelled:
            guard interactionState == .observing else { return [] }
            interactionState = .suppressedUntilMouseRelease
            presentation = .hidden
            return []

        case .pointerStateChanged(let pointerState):
            guard pointerState.leftMousePressed else {
                interactionState = .idle
                if case .guidance = presentation {
                    presentation = .hidden
                }
                return []
            }
            guard interactionState == .observing else { return [] }
            updateGuidance(optionHeld: pointerState.optionHeld)
            return []

        case .mouseReleased:
            interactionState = .idle
            if case .guidance = presentation {
                presentation = .hidden
            }
            return []

        case .modifiersChanged(let optionHeld):
            if case .guidance = presentation {
                updateGuidance(optionHeld: optionHeld)
            } else {
                selectedFormat = FormatSelection.resolve(optionHeld: optionHeld)
            }
            return []

        case .acceptedDrop(let acceptedDrop):
            interactionState = .suppressedUntilMouseRelease
            presentation = .hidden
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

        case .clipboardHandoffCompleted(let dropID, let format):
            guard dropID == activeDropID else {
                return []
            }
            activeDropID = nil
            guard case .guidance = presentation else {
                presentation = .success(format, dropID: dropID)
                return [.dismissSuccessFeedback(after: .milliseconds(800), dropID: dropID)]
            }
            return []

        case .clipboardHandoffFailed(let dropID):
            guard dropID == activeDropID else {
                return []
            }
            activeDropID = nil
            return []

        case .successFeedbackElapsed(let dropID):
            guard case .success(_, let presentedDropID) = presentation,
                  presentedDropID == dropID else {
                return []
            }
            presentation = .hidden
            return []
        }
    }

    private mutating func updateGuidance(optionHeld: Bool) {
        selectedFormat = FormatSelection.resolve(optionHeld: optionHeld)
        presentation = .guidance(selectedFormat)
    }
}
