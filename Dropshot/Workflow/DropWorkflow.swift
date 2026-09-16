nonisolated enum DropZonePresentation: Equatable, Sendable {
    case hidden
    case guidance(OutputFormat)
    case success(OutputFormat, dropID: DropID)
}

struct DropWorkflow {
    private enum InteractionState {
        case idle
        case observing
        case destination
        case releasedAtDestination
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
            guard interactionState != .suppressedUntilMouseRelease,
                  interactionState != .destination,
                  interactionState != .releasedAtDestination else {
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
            if interactionState != .releasedAtDestination {
                interactionState = .destination
            }
            updateGuidance(optionHeld: optionHeld)
            return []

        case .destinationExited,
             .destinationInteractionEnded,
             .interrupted:
            interactionState = interactionState == .releasedAtDestination
                ? .idle : .suppressedUntilMouseRelease
            presentation = .hidden
            return []

        case .cancelled:
            guard interactionState == .observing || interactionState == .destination
                || interactionState == .releasedAtDestination else { return [] }
            interactionState = interactionState == .releasedAtDestination
                ? .idle : .suppressedUntilMouseRelease
            presentation = .hidden
            return []

        case .pointerStateChanged(let pointerState):
            guard pointerState.leftMousePressed else {
                if interactionState == .destination || interactionState == .releasedAtDestination {
                    interactionState = .releasedAtDestination
                    return []
                }
                interactionState = .idle
                if case .guidance = presentation {
                    presentation = .hidden
                }
                return []
            }
            guard interactionState == .observing || interactionState == .destination
                || interactionState == .releasedAtDestination else { return [] }
            updateGuidance(optionHeld: pointerState.optionHeld)
            return []

        case .mouseReleased:
            // AppKit may deliver the authoritative drop after a monitor or polling
            // callback observes release. Keep its destination available until then.
            if interactionState == .destination || interactionState == .releasedAtDestination {
                interactionState = .releasedAtDestination
                return []
            }
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
            // The async coordinator may accept after AppKit has already ended
            // the released destination interaction. Do not wait for a second release.
            interactionState = interactionState == .releasedAtDestination || interactionState == .idle
                ? .idle : .suppressedUntilMouseRelease
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
