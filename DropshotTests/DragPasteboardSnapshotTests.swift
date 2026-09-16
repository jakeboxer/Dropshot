import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

@MainActor
struct DragPasteboardSnapshotTests {
    @Test
    func dragObserverPublishesLivePointerState() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        var pointerState = DragPointerState(leftMousePressed: true, optionHeld: false)
        var pointerStates: [DragPointerState] = []
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: { pointerState },
            onObservation: { _ in },
            onPointerStateChanged: { pointerStates.append($0) }
        )

        observer.sampleDragPasteboard()
        pointerState = DragPointerState(leftMousePressed: true, optionHeld: true)
        observer.pollPointerState()
        pointerState = DragPointerState(leftMousePressed: false, optionHeld: true)
        observer.pollPointerState()

        #expect(pointerStates == [
            DragPointerState(leftMousePressed: true, optionHeld: false),
            DragPointerState(leftMousePressed: true, optionHeld: true),
            DragPointerState(leftMousePressed: false, optionHeld: true)
        ])
    }

    @Test
    func snapshotPreservesMultipleDestinationItemsForAuthoritativeRejection() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let heicURL = URL(fileURLWithPath: "/image.heic")
        let textURL = URL(fileURLWithPath: "/notes.txt")
        let heicItem = NSPasteboardItem()
        heicItem.setString(heicURL.absoluteString, forType: .fileURL)
        heicItem.setData(Data(), forType: .init(UTType.heic.identifier))
        let textItem = NSPasteboardItem()
        textItem.setString(textURL.absoluteString, forType: .fileURL)
        textItem.setData(Data(), forType: .init(UTType.plainText.identifier))
        pasteboard.writeObjects([heicItem, textItem])

        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)

        #expect(descriptor.items?.count == 2)
        #expect(DragClassifier.classify(descriptor) == .ineligible)
        #expect(DragPasteboardSnapshot.destinationInput(from: pasteboard, descriptor: descriptor) == nil)
    }

    @Test
    func destinationSnapshotCreatesTheMatchingMaterializedInput() throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let url = URL(fileURLWithPath: "/destination-image.heic")
        #expect(pasteboard.writeObjects([url as NSURL]))
        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)

        let input = try #require(DragPasteboardSnapshot.destinationInput(
            from: pasteboard,
            descriptor: descriptor
        ))

        #expect(input.fileURL == url)
        #expect(!input.isFilePromise)
    }

    @Test
    func destinationSnapshotCreatesOnePendingHEICPromiseWithoutFulfillingIt() throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let delegate = PromiseProviderDelegate(data: Data([0x48, 0x45, 0x49, 0x43]))
        let provider = NSFilePromiseProvider(
            fileType: UTType.heic.identifier,
            delegate: delegate
        )
        #expect(pasteboard.writeObjects([provider]))

        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)
        let input = try #require(DragPasteboardSnapshot.destinationInput(
            from: pasteboard,
            descriptor: descriptor
        ))

        #expect(descriptor == DragDescriptor(items: [.filePromise(contentTypes: [.heic])]))
        #expect(input.isFilePromise)
        #expect(delegate.writeCount == 0)
    }

    @Test
    func destinationEvidenceRetainsThePromiseFromItsAuthoritativeSnapshot() throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let delegate = PromiseProviderDelegate(data: Data([0x48, 0x45, 0x49, 0x43]))
        let provider = NSFilePromiseProvider(
            fileType: UTType.heic.identifier,
            delegate: delegate
        )
        #expect(pasteboard.writeObjects([provider]))

        let evidence = DragPasteboardSnapshot.destinationEvidence(
            from: pasteboard,
            optionHeld: true
        )

        #expect(evidence.descriptor == DragDescriptor(items: [
            .filePromise(contentTypes: [.heic])
        ]))
        #expect(try #require(evidence.input).isFilePromise)
        #expect(evidence.optionHeld)
        #expect(delegate.writeCount == 0)
    }

    @Test
    func dragObserverPublishesAPasteboardSnapshotWithoutRequestingPermissions() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let url = URL(fileURLWithPath: "/observed-image.heic")
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(Data(), forType: .init(UTType.heic.identifier))
        pasteboard.writeObjects([item])
        var observations: [DragDescriptor] = []
        let observer = AppKitDragObserver(pasteboard: pasteboard) { observations.append($0) }

        observer.sampleDragPasteboard()

        #expect(observations == [DragDescriptor(items: [.fileReference(contentType: .heic)])])
    }

    @Test
    func observationDoesNotRequestLazyFileURLContents() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let provider = CountingPasteboardDataProvider()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.fileURL])
        item.setData(Data(), forType: .init(UTType.heic.identifier))
        #expect(pasteboard.writeObjects([item]))

        let observation = DragPasteboardSnapshot.observation(from: pasteboard)

        #expect(observation == DragDescriptor(items: [.fileReference(contentType: .heic)]))
        #expect(provider.requestCount == 0)
    }

    @Test
    func detectedMetadataRefinesAFileReferenceWithoutMaterializingItsURL() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let provider = CountingPasteboardDataProvider()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.fileURL])
        #expect(pasteboard.writeObjects([item]))

        let observation = DragPasteboardSnapshot.observation(
            from: pasteboard,
            detectedFileContentType: .heic
        )

        #expect(observation == DragDescriptor(items: [.fileReference(contentType: .heic)]))
        #expect(provider.requestCount == 0)
    }

    @Test
    func destinationEvidenceUsesOneAuthoritativeURLForDescriptorAndInput() throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let URL = URL(fileURLWithPath: "/destination-evidence.heic")
        #expect(pasteboard.writeObjects([URL as NSURL]))

        let evidence = DragPasteboardSnapshot.destinationEvidence(
            from: pasteboard,
            optionHeld: true
        )

        #expect(evidence.descriptor.items == [.fileURL(URL, contentType: .unknown)])
        #expect(try #require(evidence.input).fileURL == URL)
        #expect(evidence.optionHeld)
    }

    @Test
    func explicitHEICFileURLBecomesAnEligibleDragObservation() throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let url = URL(fileURLWithPath: "/observed-image.heic")
        let item = NSPasteboardItem()
        #expect(item.setString(url.absoluteString, forType: .fileURL))
        #expect(item.setData(Data(), forType: .init(UTType.heic.identifier)))
        #expect(pasteboard.writeObjects([item]))

        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)

        #expect(descriptor == DragDescriptor(items: [.fileURL(url, contentType: .heic)]))
        #expect(DragClassifier.classify(descriptor) == .eligible)
    }
}

private final class CountingPasteboardDataProvider:
    NSObject,
    NSPasteboardItemDataProvider,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var requests = 0

    nonisolated var requestCount: Int {
        lock.withLock { requests }
    }

    nonisolated func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        lock.withLock { requests += 1 }
        item.setString(URL(fileURLWithPath: "/lazy.heic").absoluteString, forType: type)
    }
}

private final class PromiseProviderDelegate:
    NSObject,
    NSFilePromiseProviderDelegate,
    @unchecked Sendable
{
    private let data: Data
    private let lock = NSLock()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var writes = 0

    nonisolated init(data: Data) {
        self.data = data
    }

    nonisolated var writeCount: Int {
        lock.withLock { writes }
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        "promised.heic"
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            try data.write(to: url)
            lock.withLock { writes += 1 }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    nonisolated func operationQueue(
        for filePromiseProvider: NSFilePromiseProvider
    ) -> OperationQueue {
        queue
    }
}
