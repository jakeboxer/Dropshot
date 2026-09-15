nonisolated protocol ImageConverting: Sendable {
    func convert(_ request: ConversionRequest) async -> Result<ConvertedImage, ImageConversionFailure>
}

@MainActor
protocol ClipboardPublishing: AnyObject {
    func publish(_ handoff: ClipboardHandoff) throws
}

@MainActor
protocol DropZonePresenting: AnyObject {
    func render(_ presentation: DropZonePresentation)
}

@MainActor
final class DropCoordinator {
    enum ConfigurationError: Error {
        case dropProcessingUnavailable
    }

    private let converter: (any ImageConverting)?
    private let clipboard: (any ClipboardPublishing)?
    private let presentation: any DropZonePresenting
    private var workflow = DropWorkflow()

    init(presentation: any DropZonePresenting) {
        converter = nil
        clipboard = nil
        self.presentation = presentation
    }

    init(
        converter: any ImageConverting,
        clipboard: any ClipboardPublishing,
        presentation: any DropZonePresenting
    ) {
        self.converter = converter
        self.clipboard = clipboard
        self.presentation = presentation
    }

    var isDropZoneRequested: Bool { workflow.isDropZoneRequested }

    func observeDrag(_ descriptor: DragDescriptor) {
        _ = workflow.handle(.dragObserved(descriptor))
        renderDropZoneRequest()
    }

    func endDestinationInteraction() {
        _ = workflow.handle(.destinationInteractionEnded)
        renderDropZoneRequest()
    }

    func destinationEntered(optionHeld: Bool) {
        handleActiveInteraction(.destinationEntered(optionHeld: optionHeld))
    }

    func destinationUpdated(optionHeld: Bool) {
        handleActiveInteraction(.destinationUpdated(optionHeld: optionHeld))
    }

    func destinationExited() {
        endInteraction(.destinationExited)
    }

    func mouseReleased() {
        endInteraction(.mouseReleased)
    }

    func interruptInteraction() {
        endInteraction(.interrupted)
    }

    func cancelInteraction() {
        endInteraction(.cancelled)
    }

    func pointerStateChanged(_ pointerState: DragPointerState) {
        let previousPresentation = workflow.presentation
        _ = workflow.handle(.pointerStateChanged(pointerState))
        if workflow.presentation != previousPresentation {
            renderDropZoneRequest()
        }
    }

    var selectedFormat: OutputFormat { workflow.selectedFormat }

    func modifiersChanged(optionHeld: Bool) {
        _ = workflow.handle(.modifiersChanged(optionHeld: optionHeld))
        renderDropZoneRequest()
    }

    func accept(_ acceptedDrop: AcceptedDrop) async throws {
        let effects = workflow.handle(.acceptedDrop(acceptedDrop))
        renderDropZoneRequest()
        try await execute(effects)
    }

    private func renderDropZoneRequest() {
        presentation.render(workflow.presentation)
    }

    private func handleActiveInteraction(_ event: DropWorkflow.Event) {
        _ = workflow.handle(event)
        renderDropZoneRequest()
    }

    private func endInteraction(_ event: DropWorkflow.Event) {
        _ = workflow.handle(event)
        renderDropZoneRequest()
    }

    private func execute(_ effects: [DropWorkflow.Effect]) async throws {
        for effect in effects {
            switch effect {
            case .convert(let request):
                guard let converter else {
                    throw ConfigurationError.dropProcessingUnavailable
                }
                let result = await converter.convert(request)
                try await execute(workflow.handle(.conversionCompleted(request: request, result: result)))

            case .performClipboardHandoff(let handoff):
                guard let clipboard else {
                    throw ConfigurationError.dropProcessingUnavailable
                }
                do {
                    try clipboard.publish(handoff)
                    let effects = workflow.handle(.clipboardHandoffCompleted(
                        dropID: handoff.dropID,
                        format: handoff.format
                    ))
                    renderDropZoneRequest()
                    try await execute(effects)
                } catch {
                    _ = workflow.handle(.clipboardHandoffFailed(dropID: handoff.dropID))
                    throw error
                }

            case .dismissSuccessFeedback(let duration, let dropID):
                Task { [weak self] in
                    try? await Task.sleep(for: duration)
                    guard !Task.isCancelled else { return }
                    self?.successFeedbackElapsed(dropID: dropID)
                }
            }
        }
    }

    private func successFeedbackElapsed(dropID: DropID) {
        _ = workflow.handle(.successFeedbackElapsed(dropID: dropID))
        renderDropZoneRequest()
    }
}
