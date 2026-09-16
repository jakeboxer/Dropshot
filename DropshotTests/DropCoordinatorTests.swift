import AppKit
import Testing
@testable import Dropshot

@MainActor
struct DropCoordinatorTests {
    @Test(arguments: [false, true])
    func realHandoffPublishesBeforeSuccessAndNewDragReplacesFeedback(optionHeld: Bool) async throws {
        let source = try #require(Bundle(for: ClipboardTestAdapter.self)
            .url(forResource: "transparency", withExtension: "heic"))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let presenter = DropZonePresentationTestAdapter()
        let coordinator = DropCoordinator(
            converter: ImageConversion(),
            clipboard: ClipboardPublication(pasteboard: pasteboard),
            presentation: presenter
        )
        let descriptor = DragDescriptor(items: [.fileURL(source, contentType: .heic)])
        try await coordinator.accept(try #require(DragClassifier.acceptDrop(
            atDestination: descriptor, input: DroppedInput(fileURL: source), optionHeld: optionHeld
        )))
        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(pasteboard.pasteboardItems?.count == 1)
        let requestedType = NSPasteboard.PasteboardType(optionHeld ? "public.png" : "public.jpeg")
        #expect(Set(item.types) == Set([requestedType, .tiff]))
        #expect(item.data(forType: requestedType)?.isEmpty == false)
        #expect(item.data(forType: .tiff)?.isEmpty == false)
        #expect(presenter.presentation == .success(optionHeld ? .png : .jpeg, dropID: DropID(1)))
        coordinator.mouseReleased()
        coordinator.observeDrag(descriptor)
        #expect(presenter.presentation == .guidance(optionHeld ? .png : .jpeg))
        try await Task.sleep(for: .milliseconds(900))
        #expect(presenter.presentation == .guidance(optionHeld ? .png : .jpeg))
    }

    @Test
    func failedClipboardHandoffThrowsWithoutPresentingSuccess() async throws {
        let presenter = DropZonePresentationTestAdapter()
        let coordinator = DropCoordinator(
            converter: ConversionTestAdapter(result: .success(ConvertedImage(
                requestedFormatData: Data([1]), tiffData: Data([2])
            ))),
            clipboard: FailingClipboardTestAdapter(),
            presentation: presenter
        )
        let source = URL(fileURLWithPath: "/unused.heic")
        let accepted = try #require(DragClassifier.acceptDrop(
            atDestination: DragDescriptor(items: [.fileURL(source, contentType: .heic)]),
            input: DroppedInput(fileURL: source)
        ))
        await #expect(throws: FailingClipboardTestAdapter.Failure.rejected) {
            try await coordinator.accept(accepted)
        }
        #expect(presenter.presentation == .hidden)
    }

    @Test
    func promisedHEICUsesTheAcceptedDropConversionAndCleansItsInput() async throws {
        let source = try #require(Bundle(for: ClipboardTestAdapter.self)
            .url(forResource: "transparency", withExtension: "heic"))
        let receipt = ReceivedInputLocation()
        let input = DroppedInput(receivePromisedFile: { directory, completion in
            let url = directory.appendingPathComponent("promised.heic")
            do {
                try FileManager.default.copyItem(at: source, to: url)
                receipt.record(url)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        })
        let clipboard = ClipboardTestAdapter()
        let coordinator = DropCoordinator(
            converter: ImageConversion(),
            clipboard: clipboard,
            presentation: DropZonePresentationTestAdapter()
        )
        try await coordinator.accept(try #require(DragClassifier.acceptDrop(
            atDestination: DragDescriptor(items: [.filePromise(contentTypes: [.heic])]),
            input: input, optionHeld: true
        )))
        let handoff = try #require(clipboard.handoffs.first)
        #expect(handoff.format == .png)
        #expect(handoff.convertedImage.requestedFormatData.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        let receivedURL = try #require(receipt.url)
        #expect(!FileManager.default.fileExists(atPath: receivedURL.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func cancelledAcceptedDropNeverPublishes() async throws {
        let url = URL(fileURLWithPath: "/cancelled.heic")
        let clipboard = ClipboardTestAdapter()
        let coordinator = DropCoordinator(
            converter: ConversionTestAdapter(result: .success(ConvertedImage(
                requestedFormatData: Data([1]), tiffData: Data([2])
            ))),
            clipboard: clipboard,
            presentation: DropZonePresentationTestAdapter()
        )
        let accepted = try #require(DragClassifier.acceptDrop(
            atDestination: DragDescriptor(items: [.fileURL(url, contentType: .heic)]),
            input: DroppedInput(fileURL: url)
        ))
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await coordinator.accept(accepted)
        }
        _ = await operation.result
        #expect(clipboard.handoffs.isEmpty)
    }

    @Test
    func stationaryEligibleDragRemainsPresentedWhileMouseButtonIsHeld() async throws {
        let presenter = DropZonePresentationTestAdapter()
        let coordinator = DropCoordinator(presentation: presenter)

        coordinator.destinationEntered(optionHeld: false)
        #expect(presenter.presentation == .guidance(.jpeg))
        coordinator.destinationUpdated(optionHeld: true)
        #expect(presenter.presentation == .guidance(.png))
        coordinator.pointerStateChanged(DragPointerState(
            leftMousePressed: true,
            optionHeld: true
        ))

        try await Task.sleep(for: .milliseconds(1_100))
        #expect(presenter.presentation == .guidance(.png))
    }

    @Test
    func destinationInteractionEndsWithoutConversionOrClipboardHandoff() async {
        let converter = ConversionTestAdapter(result: .failure(.failed))
        let clipboard = ClipboardTestAdapter()
        let presenter = DropZonePresentationTestAdapter()
        let coordinator = DropCoordinator(
            converter: converter,
            clipboard: clipboard,
            presentation: presenter
        )
        coordinator.observeDrag(DragDescriptor(items: [
            .fileURL(URL(fileURLWithPath: "/image.heic"), contentType: .heic)
        ]))
        #expect(presenter.isPresented)

        coordinator.endDestinationInteraction()

        #expect(!presenter.isPresented)
        #expect(await converter.requests.isEmpty)
        #expect(clipboard.handoffs.isEmpty)
    }

    @Test
    func eligibleDragObservationPresentsAndIneligibleObservationDismissesTheDropZone() {
        let presenter = DropZonePresentationTestAdapter()
        let coordinator = DropCoordinator(
            converter: ConversionTestAdapter(result: .failure(.failed)),
            clipboard: ClipboardTestAdapter(),
            presentation: presenter
        )
        let eligible = DragDescriptor(items: [
            .fileURL(URL(fileURLWithPath: "/image.heic"), contentType: .heic)
        ])

        coordinator.observeDrag(eligible)

        #expect(presenter.isPresented)
        coordinator.observeDrag(DragDescriptor(items: [.other]))

        #expect(!presenter.isPresented)
    }

    @Test
    func optionHeldAcceptedDropHandsOffRealPNGAndTIFF() async throws {
        let url = try #require(Bundle(for: ClipboardTestAdapter.self)
            .url(forResource: "transparency", withExtension: "heic"))
        let clipboard = ClipboardTestAdapter()
        let coordinator = DropCoordinator(
            converter: ImageConversion(),
            clipboard: clipboard,
            presentation: DropZonePresentationTestAdapter()
        )
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
        let presenter = DropZonePresentationTestAdapter()
        let coordinator = DropCoordinator(
            converter: converter,
            clipboard: clipboard,
            presentation: presenter
        )

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
        #expect(presenter.presentation == .success(.jpeg, dropID: DropID(1)))
        try await Task.sleep(for: .milliseconds(900))
        #expect(presenter.presentation == .hidden)
    }
}

@MainActor
private final class DropZonePresentationTestAdapter: DropZonePresenting {
    private(set) var presentation: DropZonePresentation = .hidden
    var isPresented: Bool { presentation != .hidden }

    func render(_ presentation: DropZonePresentation) {
        self.presentation = presentation
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

@MainActor
private final class FailingClipboardTestAdapter: ClipboardPublishing {
    enum Failure: Error { case rejected }

    func publish(_ handoff: ClipboardHandoff) throws {
        throw Failure.rejected
    }
}

private final class ReceivedInputLocation: @unchecked Sendable {
    private let lock = NSLock()
    private var value: URL?

    var url: URL? {
        lock.withLock { value }
    }

    func record(_ url: URL) {
        lock.withLock { value = url }
    }
}
