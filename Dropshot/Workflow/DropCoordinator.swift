protocol ImageConverting: Sendable {
    func convert(_ request: ConversionRequest) async -> Result<ConvertedImage, ImageConversionFailure>
}

@MainActor
protocol ClipboardPublishing: AnyObject {
    func publish(_ handoff: ClipboardHandoff) throws
}

@MainActor
protocol DropZonePresenting: AnyObject {
    func setDropZonePresented(_ isPresented: Bool)
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

    var selectedFormat: OutputFormat { workflow.selectedFormat }

    func modifiersChanged(optionHeld: Bool) {
        _ = workflow.handle(.modifiersChanged(optionHeld: optionHeld))
    }

    func accept(_ acceptedDrop: AcceptedDrop) async throws {
        let effects = workflow.handle(.acceptedDrop(acceptedDrop))
        renderDropZoneRequest()
        try await execute(effects)
    }

    private func renderDropZoneRequest() {
        presentation.setDropZonePresented(workflow.isDropZoneRequested)
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
                    _ = workflow.handle(.clipboardHandoffCompleted(dropID: handoff.dropID))
                } catch {
                    _ = workflow.handle(.clipboardHandoffFailed(dropID: handoff.dropID))
                    throw error
                }
            }
        }
    }
}
