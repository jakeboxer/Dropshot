import AppKit

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
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastPasteboardObservation: PasteboardObservation?
    private var isPollingPointerState = false

    init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag),
        pointerState: @escaping () -> DragPointerState = { .current },
        pollingScheduler: (any DragPollingScheduling)? = nil,
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
        onObservation(currentPasteboardObservation().descriptor)
        onPointerStateChanged(pointerState())
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
            if state.leftMousePressed,
               DragClassifier.classify(observation.descriptor) == .eligible {
                startPollingPointerState()
            }
        case .leftMouseUp:
            stopPollingPointerState()
            onMouseReleased()
        default:
            break
        }
    }

    private func currentPasteboardObservation() -> PasteboardObservation {
        PasteboardObservation(
            changeCount: pasteboard.changeCount,
            descriptor: DragPasteboardSnapshot.descriptor(from: pasteboard)
        )
    }

}
