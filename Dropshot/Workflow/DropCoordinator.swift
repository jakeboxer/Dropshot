protocol ImageConverting: Sendable {
    func convert(_ request: ConversionRequest) async -> Result<ConvertedImage, ImageConversionFailure>
}

@MainActor
protocol ClipboardPublishing: AnyObject {
    func perform(_ handoff: ClipboardHandoff) throws
}

@MainActor
final class DropCoordinator {
    private let converter: any ImageConverting
    private let clipboard: any ClipboardPublishing
    private var workflow = DropWorkflow()

    init(converter: any ImageConverting, clipboard: any ClipboardPublishing) {
        self.converter = converter
        self.clipboard = clipboard
    }

    func accept(_ acceptedDrop: AcceptedDrop) async throws {
        try await execute(workflow.handle(.acceptedDrop(acceptedDrop)))
    }

    private func execute(_ effects: [DropWorkflow.Effect]) async throws {
        for effect in effects {
            switch effect {
            case .convert(let request):
                let result = await converter.convert(request)
                try await execute(workflow.handle(.conversionCompleted(request: request, result: result)))

            case .performClipboardHandoff(let handoff):
                do {
                    try clipboard.perform(handoff)
                    _ = workflow.handle(.clipboardHandoffCompleted(generation: handoff.generation))
                } catch {
                    _ = workflow.handle(.clipboardHandoffFailed(generation: handoff.generation))
                    throw error
                }
            }
        }
    }
}
