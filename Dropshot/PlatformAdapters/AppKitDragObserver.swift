import AppKit

@MainActor
final class AppKitDragObserver {
    private let pasteboard: NSPasteboard
    private let onObservation: (DragDescriptor) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag),
        onObservation: @escaping (DragDescriptor) -> Void
    ) {
        self.pasteboard = pasteboard
        self.onObservation = onObservation
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor in
                self?.sampleDragPasteboard()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.sampleDragPasteboard()
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    func sampleDragPasteboard() {
        onObservation(DragPasteboardSnapshot.descriptor(from: pasteboard))
    }
}
