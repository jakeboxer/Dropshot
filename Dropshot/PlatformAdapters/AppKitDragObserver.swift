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
final class AppKitDragObserver: NSObject {
    private let pasteboard: NSPasteboard
    private let pointerState: () -> DragPointerState
    private let onObservation: (DragDescriptor) -> Void
    private let onPointerStateChanged: (DragPointerState) -> Void
    private let onMouseReleased: () -> Void
    private let onInterrupted: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?

    init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag),
        pointerState: @escaping () -> DragPointerState = { .current },
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
        super.init()
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

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
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(pollTimerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
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
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func sampleDragPasteboard() {
        onObservation(DragPasteboardSnapshot.descriptor(from: pasteboard))
        onPointerStateChanged(pointerState())
    }

    func pollPointerState() {
        onPointerStateChanged(pointerState())
    }

    @objc private func pollTimerFired() {
        pollPointerState()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            sampleDragPasteboard()
        case .leftMouseUp:
            onMouseReleased()
        default:
            break
        }
    }

}
