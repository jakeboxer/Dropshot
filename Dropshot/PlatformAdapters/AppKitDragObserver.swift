import AppKit
import UniformTypeIdentifiers

nonisolated struct DragPointerState: Equatable, Sendable {
    let leftMousePressed: Bool
    let optionHeld: Bool

    static var current: DragPointerState {
        DragPointerState(
            leftMousePressed: NSEvent.pressedMouseButtons & 1 != 0,
            optionHeld: NSEvent.modifierFlags.contains(.option)
        )
    }
}

@MainActor
protocol DragPollingScheduling: AnyObject {
    func start(_ action: @escaping () -> Void)
    func stop()
}

@MainActor
private final class RunLoopDragPollingScheduler: NSObject, DragPollingScheduling {
    private var timer: Timer?
    private var action: (() -> Void)?

    func start(_ action: @escaping () -> Void) {
        guard timer == nil else { return }

        self.action = action
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        action = nil
    }

    @objc private func timerFired() {
        action?()
    }
}

@MainActor
final class AppKitDragObserver: NSObject {
    private struct PasteboardObservation: Equatable {
        let changeCount: Int
        let descriptor: DragDescriptor
    }

    private let pasteboard: NSPasteboard
    private let pointerState: () -> DragPointerState
    private let onObservation: (DragDescriptor) -> Void
    private let onPointerStateChanged: (DragPointerState) -> Void
    private let onMouseReleased: () -> Void
    private let onInterrupted: () -> Void
    private let pollingScheduler: any DragPollingScheduling
    private let detectFileContentType: (
        NSPasteboard,
        @escaping @MainActor (UTType?) -> Void
    ) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastPasteboardObservation: PasteboardObservation?
    private var isPollingPointerState = false
    private var metadataGeneration: UInt = 0
    private var pendingMetadataChangeCount: Int?
    private var detectedMetadata: (changeCount: Int, contentType: UTType?)?

    init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag),
        pointerState: @escaping () -> DragPointerState = { .current },
        pollingScheduler: (any DragPollingScheduling)? = nil,
        detectFileContentType: ((
            NSPasteboard,
            @escaping @MainActor (UTType?) -> Void
        ) -> Void)? = nil,
        onObservation: @escaping (DragDescriptor) -> Void,
        onPointerStateChanged: @escaping (DragPointerState) -> Void = { _ in },
        onMouseReleased: @escaping () -> Void = {},
        onInterrupted: @escaping () -> Void = {}
    ) {
        self.pasteboard = pasteboard
        self.pointerState = pointerState
        self.onObservation = onObservation
        self.onPointerStateChanged = onPointerStateChanged
        self.onMouseReleased = onMouseReleased
        self.onInterrupted = onInterrupted
        self.pollingScheduler = pollingScheduler ?? RunLoopDragPollingScheduler()
        self.detectFileContentType = detectFileContentType ?? { pasteboard, completion in
            Task { @MainActor in
                let metadata = try? await pasteboard.detectedMetadata(for: [\.contentType])
                completion(metadata?.contentType)
            }
        }
        super.init()
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        lastPasteboardObservation = currentPasteboardObservation()
        // Escape can remove the HEIC payload while the physical drag continues with
        // the mouse button held. macOS provides no observable signal for that removal,
        // so guidance may remain visible until mouse release; Escape alone is not
        // evidence that the drag ended.
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        invalidateMetadataDetection()
        onInterrupted()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        stopPollingPointerState()
        lastPasteboardObservation = nil
    }

    func sampleDragPasteboard() {
        let observation = currentPasteboardObservation()
        lastPasteboardObservation = observation
        onObservation(observation.descriptor)
        let state = pointerState()
        onPointerStateChanged(state)
        requestFileContentTypeIfNeeded(for: observation, pointerState: state)
    }

    func pollPointerState() {
        onPointerStateChanged(pointerState())
    }

    private func startPollingPointerState() {
        guard !isPollingPointerState else { return }

        isPollingPointerState = true
        pollingScheduler.start { [weak self] in
            self?.pollActivePointerState()
        }
    }

    private func stopPollingPointerState() {
        isPollingPointerState = false
        pollingScheduler.stop()
    }

    private func pollActivePointerState() {
        guard isPollingPointerState else { return }

        let state = pointerState()
        onPointerStateChanged(state)
        if !state.leftMousePressed {
            invalidateMetadataDetection()
            stopPollingPointerState()
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            let observation = currentPasteboardObservation()
            guard let previousObservation = lastPasteboardObservation,
                  observation != previousObservation else { return }
            lastPasteboardObservation = observation
            onObservation(observation.descriptor)
            let state = pointerState()
            onPointerStateChanged(state)
            requestFileContentTypeIfNeeded(for: observation, pointerState: state)
            if state.leftMousePressed,
               DragClassifier.classify(observation.descriptor) == .eligible {
                startPollingPointerState()
            }
        case .leftMouseUp:
            invalidateMetadataDetection()
            stopPollingPointerState()
            onMouseReleased()
        default:
            break
        }
    }

    private func currentPasteboardObservation() -> PasteboardObservation {
        let changeCount = pasteboard.changeCount
        let contentType = detectedMetadata?.changeCount == changeCount
            ? detectedMetadata?.contentType : nil
        return PasteboardObservation(
            changeCount: changeCount,
            descriptor: DragPasteboardSnapshot.observation(
                from: pasteboard, detectedFileContentType: contentType
            )
        )
    }

    private func requestFileContentTypeIfNeeded(
        for observation: PasteboardObservation,
        pointerState state: DragPointerState
    ) {
        guard state.leftMousePressed,
              observation.descriptor.items == [.fileReference(contentType: .unknown)],
              pendingMetadataChangeCount != observation.changeCount else { return }

        metadataGeneration &+= 1
        let generation = metadataGeneration
        let changeCount = observation.changeCount
        pendingMetadataChangeCount = changeCount
        startPollingPointerState()
        detectFileContentType(pasteboard) { [weak self] contentType in
            guard let self,
                  self.metadataGeneration == generation,
                  self.pendingMetadataChangeCount == changeCount,
                  self.pasteboard.changeCount == changeCount,
                  self.pointerState().leftMousePressed else { return }

            // Keep the resolved metadata for this pasteboard revision so later
            // pointer movement cannot replace it with an unknown observation.
            self.detectedMetadata = (changeCount, contentType)
            let descriptor = DragPasteboardSnapshot.observation(
                from: self.pasteboard,
                detectedFileContentType: contentType
            )
            let refined = PasteboardObservation(changeCount: changeCount, descriptor: descriptor)
            guard refined != observation else { return }
            self.lastPasteboardObservation = refined
            self.onObservation(descriptor)
            if DragClassifier.classify(descriptor) == .eligible {
                self.startPollingPointerState()
            }
        }
    }

    private func invalidateMetadataDetection() {
        metadataGeneration &+= 1
        pendingMetadataChangeCount = nil
    }

}
