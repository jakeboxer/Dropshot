import Foundation
import Testing
@testable import Dropshot

@MainActor
struct DropCoordinatorTests {
    @Test
    func optionHeldAcceptedDropHandsOffRealPNGAndTIFF() async throws {
        let url = try #require(Bundle(for: ClipboardTestAdapter.self)
            .url(forResource: "transparency", withExtension: "heic"))
        let clipboard = ClipboardTestAdapter()
        let coordinator = DropCoordinator(converter: ImageConversion(), clipboard: clipboard)
        coordinator.modifiersChanged(optionHeld: true)
        #expect(coordinator.selectedFormat == .png)
        coordinator.modifiersChanged(optionHeld: false)
        #expect(coordinator.selectedFormat == .jpeg)
        try await coordinator.accept(try #require(DragClassifier.acceptDrop(
            atDestination: DragDescriptor(items: [.fileURL(url, contentType: .heic)]),
            input: DroppedInput(fileURL: url), optionHeld: true
        )))
        let handoff = try #require(clipboard.handoffs.first)
        #expect(clipboard.handoffs.count == 1)
        #expect(handoff.format == .png)
        #expect(handoff.convertedImage.requestedFormatData.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        #expect(handoff.convertedImage.tiffData.starts(with: [73, 73, 42, 0])
            || handoff.convertedImage.tiffData.starts(with: [77, 77, 0, 42]))
    }

    @Test
    func acceptedDropPerformsDefaultConversionAndClipboardHandoff() async throws {
        let input = DroppedInput(fileURL: URL(fileURLWithPath: "/unused-tracer.heic"))
        let jpegData = Data([0xFF, 0xD8, 0xFF])
        let tiffData = Data([0x49, 0x49, 0x2A, 0x00])
        let converter = ConversionTestAdapter(
            result: .success(ConvertedImage(requestedFormatData: jpegData, tiffData: tiffData))
        )
        let clipboard = ClipboardTestAdapter()
        let coordinator = DropCoordinator(converter: converter, clipboard: clipboard)

        try await coordinator.accept(try #require(DragClassifier.acceptDrop(
            atDestination: DragDescriptor(items: [.fileURL(input.fileURL, contentType: .heic)]), input: input
        )))

        let conversionRequests = await converter.requests
        #expect(conversionRequests == [
            ConversionRequest(dropID: DropID(1), input: input, format: .jpeg)
        ])
        #expect(clipboard.handoffs == [
            ClipboardHandoff(
                dropID: DropID(1),
                format: .jpeg,
                convertedImage: ConvertedImage(
                    requestedFormatData: jpegData,
                    tiffData: tiffData
                )
            )
        ])
    }
}

private actor ConversionTestAdapter: ImageConverting {
    private(set) var requests: [ConversionRequest] = []
    private let result: Result<ConvertedImage, ImageConversionFailure>

    init(result: Result<ConvertedImage, ImageConversionFailure>) {
        self.result = result
    }

    func convert(_ request: ConversionRequest) async -> Result<ConvertedImage, ImageConversionFailure> {
        requests.append(request)
        return result
    }
}

@MainActor
private final class ClipboardTestAdapter: ClipboardPublishing {
    private(set) var handoffs: [ClipboardHandoff] = []

    func publish(_ handoff: ClipboardHandoff) throws {
        handoffs.append(handoff)
    }
}
