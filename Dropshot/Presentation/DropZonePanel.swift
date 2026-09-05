import AppKit

nonisolated struct DropZoneGuidance: Equatable, Sendable {
    let title: String
    let subtitle: String
    let footer: String

    static let defaultJPEG = DropZoneGuidance(
        title: "Drop HEIC here",
        subtitle: "Release to copy as JPEG",
        footer: "Hold ⌥ for PNG"
    )
}

@MainActor
final class DropZonePanelController: DropZonePresenting {
    let panel: DropZonePanel
    let guidance = DropZoneGuidance.defaultJPEG

    private let dropView: DropZoneView
    private let onAcceptedDrop: (AcceptedDrop) -> Void
    private let onRejectedDrop: () -> Void
    private weak var anchorView: NSView?

    init(
        onAcceptedDrop: @escaping (AcceptedDrop) -> Void = { _ in },
        onRejectedDrop: @escaping () -> Void = {}
    ) {
        self.onAcceptedDrop = onAcceptedDrop
        self.onRejectedDrop = onRejectedDrop
        dropView = DropZoneView(guidance: guidance)
        panel = DropZonePanel(contentView: dropView)
        dropView.onDestinationDrop = { [weak self] evidence in
            self?.acceptDestinationDrop(evidence) ?? false
        }
    }

    var registeredDraggedTypes: [NSPasteboard.PasteboardType] {
        dropView.registeredDraggedTypes
    }

    func anchor(to view: NSView?) {
        anchorView = view
    }

    func setDropZonePresented(_ isPresented: Bool) {
        if isPresented {
            positionBelowAnchor()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    @discardableResult
    func acceptDestinationDrop(_ evidence: DestinationDropEvidence) -> Bool {
        guard let input = evidence.input,
              let acceptedDrop = DragClassifier.acceptDrop(
                atDestination: evidence.descriptor,
                input: input,
                optionHeld: evidence.optionHeld
              ) else {
            onRejectedDrop()
            return false
        }
        onAcceptedDrop(acceptedDrop)
        return true
    }

    private func positionBelowAnchor() {
        guard let anchorView, let anchorWindow = anchorView.window else { return }
        let anchorFrame = anchorWindow.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        panel.setFrameOrigin(NSPoint(
            x: anchorFrame.midX - panel.frame.width / 2,
            y: anchorFrame.minY - 8 - panel.frame.height
        ))
    }
}

@MainActor
final class DropZonePanel: NSPanel {
    static let contentSize = NSSize(width: 202, height: 170)

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        self.contentView = contentView
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.transient]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DropZoneView: NSVisualEffectView {
    var onDestinationDrop: (DestinationDropEvidence) -> Bool = { _ in false }

    init(guidance: DropZoneGuidance) {
        super.init(frame: NSRect(origin: .zero, size: DropZonePanel.contentSize))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 30
        layer?.masksToBounds = true

        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType(rawValue: $0)
        }
        registerForDraggedTypes([.fileURL] + promiseTypes)
        installContent(guidance)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isEligibleDestination(sender) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isEligibleDestination(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)
        return onDestinationDrop(DestinationDropEvidence(
            descriptor: descriptor,
            input: DragPasteboardSnapshot.singleFileInput(from: descriptor),
            optionHeld: NSEvent.modifierFlags.contains(.option)
        ))
    }

    private func isEligibleDestination(_ sender: any NSDraggingInfo) -> Bool {
        DragClassifier.classify(DragPasteboardSnapshot.descriptor(from: sender.draggingPasteboard)) == .eligible
    }

    private func installContent(_ guidance: DropZoneGuidance) {
        let symbol = NSImageView(image: NSImage(
            systemSymbolName: "arrow.down",
            accessibilityDescription: guidance.title
        ) ?? NSImage())
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 25, weight: .semibold)
        symbol.contentTintColor = .controlAccentColor

        let formatOrb = NSView()
        formatOrb.wantsLayer = true
        formatOrb.layer?.cornerRadius = 31
        formatOrb.layer?.borderWidth = 2
        formatOrb.layer?.borderColor = NSColor.controlAccentColor.cgColor
        formatOrb.translatesAutoresizingMaskIntoConstraints = false
        symbol.translatesAutoresizingMaskIntoConstraints = false
        formatOrb.addSubview(symbol)

        NSLayoutConstraint.activate([
            formatOrb.widthAnchor.constraint(equalToConstant: 62),
            formatOrb.heightAnchor.constraint(equalToConstant: 62),
            symbol.centerXAnchor.constraint(equalTo: formatOrb.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: formatOrb.centerYAnchor)
        ])

        let title = label(guidance.title, size: 15, weight: .semibold, color: .labelColor)
        let subtitle = label(guidance.subtitle, size: 12, weight: .medium, color: .secondaryLabelColor)
        let footer = label(guidance.footer, size: 11, weight: .regular, color: .tertiaryLabelColor)
        let stack = NSStackView(views: [formatOrb, title, subtitle, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.setCustomSpacing(8, after: formatOrb)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            trailingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 12)
        ])
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
