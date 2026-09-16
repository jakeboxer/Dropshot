import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

@MainActor
@Suite(.serialized)
struct AppKitDragObserverTests {
    @Test
    func metadataRefinementSurvivesFurtherPointerMovementWithoutAnotherRequest() throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var completions: [@MainActor (UTType?) -> Void] = []
        var observations: [DragDescriptor] = []
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: { DragPointerState(leftMousePressed: true, optionHeld: false) },
            pollingScheduler: ManualDragPollingScheduler(),
            detectFileContentType: { _, completion in completions.append(completion) },
            onObservation: { observations.append($0) }
        )
        observer.start()
        defer { observer.stop() }
        #expect(pasteboard.writeObjects([URL(fileURLWithPath: "/metadata.heic") as NSURL]))
        try dispatchSyntheticMouseDrag()
        #expect(completions.count == 1)
        let completion = try #require(completions.first)
        completion(.heic)
        #expect(observations.last == DragDescriptor(items: [.fileReference(contentType: .heic)]))
        let countAfterRefinement = observations.count
        try dispatchSyntheticMouseDrag()
        #expect(observations.count == countAfterRefinement)
        #expect(completions.count == 1)
    }

    @Test(arguments: ["release", "stop", "replace", "polledRelease"])
    func staleMetadataCannotRestoreGuidance(after boundary: String) throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var completions: [@MainActor (UTType?) -> Void] = []
        var observations: [DragDescriptor] = []
        var pressed = true
        let scheduler = ManualDragPollingScheduler()
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: { DragPointerState(leftMousePressed: pressed, optionHeld: false) },
            pollingScheduler: scheduler,
            detectFileContentType: { _, completion in completions.append(completion) },
            onObservation: { observations.append($0) }
        )
        observer.start()
        defer { observer.stop() }
        #expect(pasteboard.writeObjects([URL(fileURLWithPath: "/stale.heic") as NSURL]))
        try dispatchSyntheticMouseDrag()
        let completion = try #require(completions.first)
        switch boundary {
        case "release": try dispatchSyntheticMouseUp()
        case "stop": observer.stop()
        case "replace":
            pasteboard.clearContents()
            #expect(pasteboard.setString("replacement", forType: .string))
        default:
            pressed = false
            scheduler.fire()
            pressed = true
        }
        let countBeforeCompletion = observations.count
        completion(.heic)
        #expect(observations.count == countBeforeCompletion)
    }

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
    func explicitMouseReleaseStopsPollingAndTheNextEligibleDragRestartsIt() throws {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let scheduler = ManualDragPollingScheduler()
        let presenter = AppKitDragObserverPresentationTestAdapter()
        let coordinator = DropCoordinator(presentation: presenter)
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: {
                DragPointerState(leftMousePressed: true, optionHeld: false)
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

        #expect(scheduler.isRunning)
        #expect(scheduler.startCount == 1)

        try dispatchSyntheticMouseUp()

        #expect(!scheduler.isRunning)
        #expect(presenter.presentation == .hidden)

        pasteboard.clearContents()
        try writeEligibleHEIC(to: pasteboard)
        try dispatchSyntheticMouseDrag()

        #expect(scheduler.isRunning)
        #expect(scheduler.startCount == 2)
        #expect(presenter.presentation == .guidance(.jpeg))
    }

    @Test
    func repeatedFreshObservationsReusePollingAndStoppingObserverCancelsIt() throws {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let scheduler = ManualDragPollingScheduler()
        let observer = AppKitDragObserver(
            pasteboard: pasteboard,
            pointerState: {
                DragPointerState(leftMousePressed: true, optionHeld: false)
            },
            pollingScheduler: scheduler,
            onObservation: { _ in }
        )
        observer.start()
        defer { observer.stop() }
        try writeEligibleHEIC(to: pasteboard)
        try dispatchSyntheticMouseDrag()
        pasteboard.clearContents()
        try writeEligibleHEIC(to: pasteboard)
        try dispatchSyntheticMouseDrag()

        #expect(scheduler.isRunning)
        #expect(scheduler.startCount == 1)

        observer.stop()

        #expect(!scheduler.isRunning)
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

    private func dispatchSyntheticMouseUp() throws {
        let mouseUp = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        NSApplication.shared.postEvent(mouseUp, atStart: true)
        let dispatchedMouseUp = try #require(NSApplication.shared.nextEvent(
            matching: .leftMouseUp,
            until: Date(timeIntervalSinceNow: 1),
            inMode: .default,
            dequeue: true
        ))
        NSApplication.shared.sendEvent(dispatchedMouseUp)
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
    private(set) var startCount = 0

    func start(_ action: @escaping () -> Void) {
        startCount += 1
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
