import Foundation
import Testing
@testable import Dropshot

@MainActor
struct DropCoordinatorTests {
    @Test
    func acceptedDropPerformsDefaultConversionAndClipboardHandoff() async throws {
        let input = DroppedInput()
        let jpegData = Data([0xFF, 0xD8, 0xFF])
        let tiffData = Data([0x49, 0x49, 0x2A, 0x00])
        let converter = ConversionTestAdapter(
            result: .success(ConvertedImage(requestedFormatData: jpegData, tiffData: tiffData))
        )
        let clipboard = ClipboardTestAdapter()
        let coordinator = DropCoordinator(converter: converter, clipboard: clipboard)

        try await coordinator.accept(AcceptedDrop(input: input))

        let conversionRequests = await converter.requests
        #expect(conversionRequests == [
            ConversionRequest(dropID: DropID(1), input: input, format: .jpeg)
        ])
        #expect(clipboard.handoffs == [
            ClipboardHandoff(
                dropID: DropID(1),
                format: .jpeg,
                requestedFormatData: jpegData,
                tiffData: tiffData
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

    func perform(_ handoff: ClipboardHandoff) throws {
        handoffs.append(handoff)
    }
}
