import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

@MainActor
@Suite(.serialized)
struct AppKitDragObserverTests {
    @Test
    func observerDoesNotPollWhileNoEligibleDragIsActive() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let scheduler = ManualDragPollingScheduler()
        var pointerStateReadCount = 0
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: {
                pointerStateReadCount += 1
                return DragPointerState(leftMousePressed: true, optionHeld: false)
            },
            pollingScheduler: scheduler,
            onObservation: { _ in }
        )
        observer.start()
        defer { observer.stop() }

        #expect(!scheduler.isRunning)
        scheduler.fire()

        #expect(pointerStateReadCount == 0)
    }

    @Test
    func eligibleDragPollsStationaryPointerStateAndUpdatesGuidance() throws {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        var pointerState = DragPointerState(leftMousePressed: true, optionHeld: false)
        let scheduler = ManualDragPollingScheduler()
        let presenter = AppKitDragObserverPresentationTestAdapter()
        let coordinator = DropCoordinator(presentation: presenter)
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: { pointerState },
            pollingScheduler: scheduler,
            onObservation: coordinator.observeDrag,
            onPointerStateChanged: coordinator.pointerStateChanged,
            onMouseReleased: coordinator.mouseReleased,
            onInterrupted: coordinator.interruptInteraction
        )
        observer.start()
        defer { observer.stop() }
        try writeEligibleHEIC(to: pasteboard)
        try dispatchSyntheticMouseDrag()
        #expect(presenter.presentation == .guidance(.jpeg))
        #expect(scheduler.isRunning)

        pointerState = DragPointerState(leftMousePressed: true, optionHeld: true)
        scheduler.fire()

        #expect(presenter.presentation == .guidance(.png))
    }

    @Test
    func pollingStopsWhenTheDragInteractionEnds() throws {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        var pointerState = DragPointerState(leftMousePressed: true, optionHeld: false)
        var pointerStateReadCount = 0
        let scheduler = ManualDragPollingScheduler()
        let presenter = AppKitDragObserverPresentationTestAdapter()
        let coordinator = DropCoordinator(presentation: presenter)
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: {
                pointerStateReadCount += 1
                return pointerState
            },
            pollingScheduler: scheduler,
            onObservation: coordinator.observeDrag,
            onPointerStateChanged: coordinator.pointerStateChanged,
            onMouseReleased: coordinator.mouseReleased,
            onInterrupted: coordinator.interruptInteraction
        )
        observer.start()
        defer { observer.stop() }
        try writeEligibleHEIC(to: pasteboard)
        try dispatchSyntheticMouseDrag()
        #expect(presenter.presentation == .guidance(.jpeg))
        #expect(scheduler.isRunning)
        let readsBeforeRelease = pointerStateReadCount

        pointerState = DragPointerState(leftMousePressed: false, optionHeld: false)
        scheduler.fire()
        #expect(presenter.presentation == .hidden)
        #expect(pointerStateReadCount > readsBeforeRelease)
        #expect(!scheduler.isRunning)
        let readsAfterInteractionEnded = pointerStateReadCount

        pointerState = DragPointerState(leftMousePressed: true, optionHeld: true)
        scheduler.fire()

        #expect(pointerStateReadCount == readsAfterInteractionEnded)
        #expect(presenter.presentation == .hidden)
    }

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

    private func writeEligibleHEIC(to pasteboard: NSPasteboard) throws {
        let heicURL = URL(fileURLWithPath: "/polling-lifecycle.heic")
        let heicItem = NSPasteboardItem()
        #expect(heicItem.setString(heicURL.absoluteString, forType: .fileURL))
        #expect(heicItem.setData(Data(), forType: .init(UTType.heic.identifier)))
        #expect(pasteboard.writeObjects([heicItem]))
    }
}

@MainActor
private final class ManualDragPollingScheduler: DragPollingScheduling {
    private var action: (() -> Void)?
    var isRunning: Bool { action != nil }

    func start(_ action: @escaping () -> Void) {
        self.action = action
    }

    func stop() {
        action = nil
    }

    func fire() {
        action?()
    }
}

@MainActor
private final class AppKitDragObserverPresentationTestAdapter: DropZonePresenting {
    private(set) var presentation: DropZonePresentation = .hidden

    func render(_ presentation: DropZonePresentation) {
        self.presentation = presentation
    }
}
