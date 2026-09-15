import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

@MainActor
@Suite(.serialized)
struct AppKitDragObserverTests {
    @Test
    func ordinaryMouseDragDoesNotPresentDropZoneFromUnrelatedDragPasteboardContents() throws {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let unrelatedURL = URL(fileURLWithPath: "/unrelated-image.heic")
        let unrelatedItem = NSPasteboardItem()
        #expect(unrelatedItem.setString(unrelatedURL.absoluteString, forType: .fileURL))
        #expect(unrelatedItem.setData(Data(), forType: .init(UTType.heic.identifier)))
        #expect(pasteboard.writeObjects([unrelatedItem]))

        let presenter = AppKitDragObserverPresentationTestAdapter()
        let coordinator = DropCoordinator(presentation: presenter)
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: {
                DragPointerState(leftMousePressed: true, optionHeld: false)
            },
            onObservation: coordinator.observeDrag,
            onPointerStateChanged: coordinator.pointerStateChanged,
            onMouseReleased: coordinator.mouseReleased,
            onInterrupted: coordinator.interruptInteraction
        )
        observer.start()
        defer { observer.stop() }

        try dispatchSyntheticMouseDrag()

        #expect(presenter.presentation == .hidden)
    }

    @Test
    func freshHEICDragPresentsJPEGGuidance() throws {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let presenter = AppKitDragObserverPresentationTestAdapter()
        let coordinator = DropCoordinator(presentation: presenter)
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: {
                DragPointerState(leftMousePressed: true, optionHeld: false)
            },
            onObservation: coordinator.observeDrag,
            onPointerStateChanged: coordinator.pointerStateChanged,
            onMouseReleased: coordinator.mouseReleased,
            onInterrupted: coordinator.interruptInteraction
        )
        observer.start()
        defer { observer.stop() }

        let heicURL = URL(fileURLWithPath: "/fresh-image.heic")
        let heicItem = NSPasteboardItem()
        #expect(heicItem.setString(heicURL.absoluteString, forType: .fileURL))
        #expect(heicItem.setData(Data(), forType: .init(UTType.heic.identifier)))
        #expect(pasteboard.writeObjects([heicItem]))

        try dispatchSyntheticMouseDrag()

        #expect(presenter.presentation == .guidance(.jpeg))
    }

    private func dispatchSyntheticMouseDrag() throws {
        let mouseDrag = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        NSApplication.shared.postEvent(mouseDrag, atStart: true)
        let dispatchedMouseDrag = try #require(NSApplication.shared.nextEvent(
            matching: .leftMouseDragged,
            until: Date(timeIntervalSinceNow: 1),
            inMode: .default,
            dequeue: true
        ))
        NSApplication.shared.sendEvent(dispatchedMouseDrag)
    }
}

@MainActor
private final class AppKitDragObserverPresentationTestAdapter: DropZonePresenting {
    private(set) var presentation: DropZonePresentation = .hidden

    func render(_ presentation: DropZonePresentation) {
        self.presentation = presentation
    }
}
